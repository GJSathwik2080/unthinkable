-- Business workflows. These functions are called only by verified Next.js server routes.
create or replace function public.current_role(p_user_id uuid)
returns public.user_role
language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p where p.id = p_user_id;
$$;

create or replace function public.enqueue_status_notifications(p_event_id uuid, p_order_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_customer_id uuid;
  v_email text;
  v_phone text;
begin
  select o.customer_id, u.email, p.phone into v_customer_id, v_email, v_phone
  from public.orders o
  join public.profiles p on p.id = o.customer_id
  left join auth.users u on u.id = o.customer_id
  where o.id = p_order_id;

  if v_email is not null then
    insert into public.notification_outbox (order_event_id, order_id, recipient, channel)
    values (p_event_id, p_order_id, v_email, 'EMAIL')
    on conflict (order_event_id, channel) do nothing;
  end if;

  if v_phone is not null then
    insert into public.notification_outbox (order_event_id, order_id, recipient, channel)
    values (p_event_id, p_order_id, v_phone, 'SMS')
    on conflict (order_event_id, channel) do nothing;
  end if;
end;
$$;

create or replace function public.calculate_order_quote(
  p_pickup_postal_code text,
  p_drop_postal_code text,
  p_length_cm numeric,
  p_breadth_cm numeric,
  p_height_cm numeric,
  p_actual_weight_kg numeric,
  p_order_type public.order_type,
  p_payment_type public.payment_type
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pickup record;
  v_drop record;
  v_settings public.pricing_settings%rowtype;
  v_rate public.rate_cards%rowtype;
  v_cod integer := 0;
  v_volumetric integer;
  v_actual integer;
  v_billable integer;
  v_steps integer;
  v_additional integer;
begin
  if p_length_cm <= 0 or p_breadth_cm <= 0 or p_height_cm <= 0 or p_actual_weight_kg <= 0 then
    raise exception 'Package dimensions and actual weight must be greater than zero';
  end if;

  select a.id as area_id, a.name as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
  into v_pickup
  from public.service_area_postal_codes pc
  join public.service_areas a on a.id = pc.service_area_id and a.is_active
  join public.zones z on z.id = a.zone_id and z.is_active
  where pc.postal_code = trim(p_pickup_postal_code) and pc.is_active;
  if not found then raise exception 'Pickup postal code is not serviceable'; end if;

  select a.id as area_id, a.name as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
  into v_drop
  from public.service_area_postal_codes pc
  join public.service_areas a on a.id = pc.service_area_id and a.is_active
  join public.zones z on z.id = a.zone_id and z.is_active
  where pc.postal_code = trim(p_drop_postal_code) and pc.is_active;
  if not found then raise exception 'Drop postal code is not serviceable'; end if;

  select * into v_settings from public.pricing_settings where id = true;
  if not found then raise exception 'Pricing settings are unavailable'; end if;

  select * into v_rate
  from public.rate_cards
  where pickup_zone_id = v_pickup.zone_id
    and drop_zone_id = v_drop.zone_id
    and order_type = p_order_type
    and is_active
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc
  limit 1;
  if not found then raise exception 'No active rate card exists for this route and order type'; end if;

  if p_payment_type = 'COD' then
    select surcharge_minor into v_cod from public.cod_surcharges where order_type = p_order_type and is_active;
    if not found then raise exception 'No active COD surcharge exists for this order type'; end if;
  end if;

  v_volumetric := ceil((p_length_cm * p_breadth_cm * p_height_cm / v_settings.volumetric_divisor) * 1000)::integer;
  v_actual := round(p_actual_weight_kg * 1000)::integer;
  v_billable := ceil(greatest(v_volumetric, v_actual)::numeric / v_settings.rounding_grams) * v_settings.rounding_grams;
  v_steps := ceil(greatest(0, v_billable - v_rate.base_weight_grams)::numeric / v_rate.additional_step_grams);
  v_additional := v_steps * v_rate.additional_step_charge_minor;

  return jsonb_build_object(
    'pickupAreaId', v_pickup.area_id, 'pickupAreaName', v_pickup.area_name, 'pickupZoneId', v_pickup.zone_id, 'pickupZoneName', v_pickup.zone_name,
    'dropAreaId', v_drop.area_id, 'dropAreaName', v_drop.area_name, 'dropZoneId', v_drop.zone_id, 'dropZoneName', v_drop.zone_name,
    'movementType', case when v_pickup.zone_id = v_drop.zone_id then 'INTRA_ZONE' else 'INTER_ZONE' end,
    'rateCardId', v_rate.id, 'volumetricDivisor', v_settings.volumetric_divisor, 'roundingGrams', v_settings.rounding_grams,
    'actualWeightGrams', v_actual, 'volumetricWeightGrams', v_volumetric, 'billableWeightGrams', v_billable,
    'baseChargeMinor', v_rate.base_charge_minor, 'additionalChargeMinor', v_additional, 'codChargeMinor', v_cod,
    'totalChargeMinor', v_rate.base_charge_minor + v_additional + v_cod, 'currency', v_settings.currency
  );
end;
$$;

create or replace function public.create_order(
  p_customer_id uuid,
  p_created_by_user_id uuid,
  p_order jsonb,
  p_scheduled_delivery_date date default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_quote jsonb;
  v_order_id uuid := gen_random_uuid();
  v_event_id uuid;
  v_tracking text := 'LM-' || upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8));
  v_customer_role public.user_role;
  v_creator_role public.user_role;
begin
  select role into v_customer_role from public.profiles where id = p_customer_id and is_active;
  if not found or v_customer_role <> 'CUSTOMER' then raise exception 'Order customer must be an active customer account'; end if;
  select role into v_creator_role from public.profiles where id = p_created_by_user_id and is_active;
  if not found or v_creator_role not in ('CUSTOMER', 'ADMIN') then raise exception 'Order creator is not authorized'; end if;
  if v_creator_role = 'CUSTOMER' and p_customer_id <> p_created_by_user_id then raise exception 'Customers can create orders only for themselves'; end if;

  v_quote := public.calculate_order_quote(
    p_order #>> '{pickup,postalCode}', p_order #>> '{drop,postalCode}',
    (p_order ->> 'lengthCm')::numeric, (p_order ->> 'breadthCm')::numeric, (p_order ->> 'heightCm')::numeric,
    (p_order ->> 'actualWeightKg')::numeric, (p_order ->> 'orderType')::public.order_type, (p_order ->> 'paymentType')::public.payment_type
  );

  insert into public.orders (id, tracking_number, customer_id, created_by_user_id, order_type, payment_type, scheduled_delivery_date)
  values (v_order_id, v_tracking, p_customer_id, p_created_by_user_id, (p_order ->> 'orderType')::public.order_type, (p_order ->> 'paymentType')::public.payment_type, p_scheduled_delivery_date);

  insert into public.order_addresses (order_id, address_type, recipient_name, recipient_phone, address_line_1, address_line_2, service_area_id, area_name_snapshot, postal_code_snapshot, zone_id_snapshot)
  values
  (v_order_id, 'PICKUP', p_order #>> '{pickup,recipientName}', p_order #>> '{pickup,phone}', p_order #>> '{pickup,addressLine1}', nullif(p_order #>> '{pickup,addressLine2}', ''), (v_quote ->> 'pickupAreaId')::uuid, v_quote ->> 'pickupAreaName', p_order #>> '{pickup,postalCode}', (v_quote ->> 'pickupZoneId')::uuid),
  (v_order_id, 'DROP', p_order #>> '{drop,recipientName}', p_order #>> '{drop,phone}', p_order #>> '{drop,addressLine1}', nullif(p_order #>> '{drop,addressLine2}', ''), (v_quote ->> 'dropAreaId')::uuid, v_quote ->> 'dropAreaName', p_order #>> '{drop,postalCode}', (v_quote ->> 'dropZoneId')::uuid);

  insert into public.order_pricing_snapshots (order_id, rate_card_id, volumetric_divisor, rounding_grams, actual_weight_grams, volumetric_weight_grams, billable_weight_grams, base_charge_minor, additional_charge_minor, cod_charge_minor, total_charge_minor, currency)
  values (v_order_id, (v_quote ->> 'rateCardId')::uuid, (v_quote ->> 'volumetricDivisor')::integer, (v_quote ->> 'roundingGrams')::integer, (v_quote ->> 'actualWeightGrams')::integer, (v_quote ->> 'volumetricWeightGrams')::integer, (v_quote ->> 'billableWeightGrams')::integer, (v_quote ->> 'baseChargeMinor')::integer, (v_quote ->> 'additionalChargeMinor')::integer, (v_quote ->> 'codChargeMinor')::integer, (v_quote ->> 'totalChargeMinor')::integer, v_quote ->> 'currency');

  insert into public.delivery_attempts (order_id, attempt_number, scheduled_date) values (v_order_id, 1, p_scheduled_delivery_date);
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (v_order_id, 'PLACED', p_created_by_user_id, public.current_role(p_created_by_user_id)::text, 'Order created') returning id into v_event_id;
  perform public.enqueue_status_notifications(v_event_id, v_order_id);
  return v_order_id;
end;
$$;

create or replace function public.auto_assign_order(p_order_id uuid, p_actor_user_id uuid, p_excluded_agent_id uuid default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_attempt_id uuid;
  v_pickup_zone_id uuid;
  v_pickup_lat numeric;
  v_pickup_lng numeric;
  v_agent_id uuid;
  v_event_id uuid;
begin
  select da.id into v_attempt_id from public.delivery_attempts da where da.order_id = p_order_id and da.status = 'SCHEDULED' order by da.attempt_number desc limit 1 for update;
  if v_attempt_id is null then raise exception 'Order has no scheduled delivery attempt available for assignment'; end if;

  select oa.zone_id_snapshot, sa.latitude, sa.longitude into v_pickup_zone_id, v_pickup_lat, v_pickup_lng
  from public.order_addresses oa left join public.service_areas sa on sa.id = oa.service_area_id
  where oa.order_id = p_order_id and oa.address_type = 'PICKUP';

  select ap.user_id into v_agent_id
  from public.agent_profiles ap
  left join public.delivery_assignments active_assignment on active_assignment.agent_id = ap.user_id and active_assignment.is_active
  where ap.availability = 'AVAILABLE' and active_assignment.id is null and (p_excluded_agent_id is null or ap.user_id <> p_excluded_agent_id)
  order by
    (ap.home_zone_id = v_pickup_zone_id) desc,
    (ap.location_updated_at >= now() - interval '15 minutes' and ap.current_latitude is not null and v_pickup_lat is not null) desc,
    case when ap.location_updated_at >= now() - interval '15 minutes' and ap.current_latitude is not null and v_pickup_lat is not null then
      6371 * acos(least(1.0, greatest(-1.0, cos(radians(v_pickup_lat)) * cos(radians(ap.current_latitude)) * cos(radians(ap.current_longitude) - radians(v_pickup_lng)) + sin(radians(v_pickup_lat)) * sin(radians(ap.current_latitude)))))
    end asc nulls last,
    ap.last_assigned_at asc nulls first
  for update of ap skip locked limit 1;

  if v_agent_id is null and p_excluded_agent_id is not null then
    return public.auto_assign_order(p_order_id, p_actor_user_id, null);
  end if;
  if v_agent_id is null then return null; end if;

  insert into public.delivery_assignments (attempt_id, agent_id, assigned_by_user_id, method) values (v_attempt_id, v_agent_id, p_actor_user_id, case when p_excluded_agent_id is null then 'AUTO' else 'RESCHEDULE' end);
  update public.delivery_attempts set status = 'ACTIVE' where id = v_attempt_id;
  update public.agent_profiles set availability = 'BUSY', last_assigned_at = now() where user_id = v_agent_id;
  update public.orders set current_status = 'ASSIGNED' where id = p_order_id;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (p_order_id, 'ASSIGNED', p_actor_user_id, public.current_role(p_actor_user_id)::text, 'Agent assigned automatically') returning id into v_event_id;
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
  return v_agent_id;
end;
$$;

create or replace function public.assign_order_manually(p_order_id uuid, p_agent_id uuid, p_actor_user_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_attempt_id uuid; v_event_id uuid;
begin
  select id into v_attempt_id from public.delivery_attempts where order_id = p_order_id and status = 'SCHEDULED' order by attempt_number desc limit 1 for update;
  if v_attempt_id is null then raise exception 'Order has no scheduled attempt available for assignment'; end if;
  perform 1 from public.agent_profiles ap where ap.user_id = p_agent_id and ap.availability = 'AVAILABLE' for update;
  if not found or exists (select 1 from public.delivery_assignments where agent_id = p_agent_id and is_active) then raise exception 'Selected agent is not eligible'; end if;
  insert into public.delivery_assignments (attempt_id, agent_id, assigned_by_user_id, method) values (v_attempt_id, p_agent_id, p_actor_user_id, 'MANUAL');
  update public.delivery_attempts set status = 'ACTIVE' where id = v_attempt_id;
  update public.agent_profiles set availability = 'BUSY', last_assigned_at = now() where user_id = p_agent_id;
  update public.orders set current_status = 'ASSIGNED' where id = p_order_id;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (p_order_id, 'ASSIGNED', p_actor_user_id, public.current_role(p_actor_user_id)::text, 'Agent assigned manually') returning id into v_event_id;
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
end;
$$;

create or replace function public.transition_order_status(p_order_id uuid, p_next_status public.order_status, p_actor_user_id uuid, p_note text default null, p_failure_reason text default null, p_is_override boolean default false)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_current public.order_status;
  v_role public.user_role;
  v_attempt_id uuid;
  v_agent_id uuid;
  v_event_id uuid;
  v_valid boolean := false;
begin
  select current_status into v_current from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  v_role := public.current_role(p_actor_user_id);
  if v_role is null then raise exception 'Actor profile not found'; end if;

  select da.id, a.agent_id into v_attempt_id, v_agent_id from public.delivery_attempts da join public.delivery_assignments a on a.attempt_id = da.id and a.is_active where da.order_id = p_order_id and da.status = 'ACTIVE' order by da.attempt_number desc limit 1 for update;
  if v_role = 'DELIVERY_AGENT' and v_agent_id is distinct from p_actor_user_id then raise exception 'Agent is not assigned to this order'; end if;
  if v_role = 'CUSTOMER' then raise exception 'Customers cannot change delivery status'; end if;

  v_valid := (v_current = 'ASSIGNED' and p_next_status in ('PICKED_UP', 'FAILED')) or
             (v_current = 'PICKED_UP' and p_next_status in ('IN_TRANSIT', 'FAILED')) or
             (v_current = 'IN_TRANSIT' and p_next_status in ('OUT_FOR_DELIVERY', 'FAILED')) or
             (v_current = 'OUT_FOR_DELIVERY' and p_next_status in ('DELIVERED', 'FAILED'));
  if not v_valid and not (v_role = 'ADMIN' and p_is_override and coalesce(trim(p_note), '') <> '') then
    raise exception 'Invalid status transition';
  end if;
  if p_next_status = 'FAILED' and coalesce(trim(p_failure_reason), '') = '' then raise exception 'Failed delivery requires a reason'; end if;

  update public.orders set current_status = p_next_status where id = p_order_id;
  if p_next_status = 'PICKED_UP' then update public.delivery_attempts set started_at = coalesce(started_at, now()) where id = v_attempt_id; end if;
  if p_next_status = 'DELIVERED' then
    update public.delivery_attempts set status = 'DELIVERED', completed_at = now() where id = v_attempt_id;
    update public.delivery_assignments set is_active = false, released_at = now(), release_reason = 'Delivered' where attempt_id = v_attempt_id and is_active;
    update public.agent_profiles set availability = 'AVAILABLE' where user_id = v_agent_id;
  elsif p_next_status = 'FAILED' then
    update public.delivery_attempts set status = 'FAILED', failure_reason = p_failure_reason, completed_at = now() where id = v_attempt_id;
    update public.delivery_assignments set is_active = false, released_at = now(), release_reason = 'Delivery failed' where attempt_id = v_attempt_id and is_active;
    update public.agent_profiles set availability = 'AVAILABLE' where user_id = v_agent_id;
  end if;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note, is_override) values (p_order_id, p_next_status, p_actor_user_id, v_role::text, coalesce(p_failure_reason, p_note), p_is_override) returning id into v_event_id;
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
end;
$$;

create or replace function public.reschedule_failed_order(p_order_id uuid, p_actor_user_id uuid, p_scheduled_date date)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_customer uuid; v_role public.user_role; v_previous_agent uuid; v_attempt_number integer; v_event_id uuid; v_agent uuid;
begin
  select customer_id into v_customer from public.orders where id = p_order_id and current_status = 'FAILED' for update;
  if not found then raise exception 'Only failed orders can be rescheduled'; end if;
  v_role := public.current_role(p_actor_user_id);
  if p_actor_user_id <> v_customer and v_role <> 'ADMIN' then raise exception 'Only the customer or an admin can reschedule this order'; end if;
  if p_scheduled_date <= current_date then raise exception 'Rescheduled delivery date must be in the future'; end if;
  select a.agent_id into v_previous_agent from public.delivery_attempts da join public.delivery_assignments a on a.attempt_id = da.id where da.order_id = p_order_id order by da.attempt_number desc, a.created_at desc limit 1;
  select coalesce(max(attempt_number), 0) + 1 into v_attempt_number from public.delivery_attempts where order_id = p_order_id;
  insert into public.delivery_attempts (order_id, attempt_number, scheduled_date) values (p_order_id, v_attempt_number, p_scheduled_date);
  update public.orders set current_status = 'RESCHEDULED', scheduled_delivery_date = p_scheduled_date where id = p_order_id;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (p_order_id, 'RESCHEDULED', p_actor_user_id, v_role::text, 'Delivery rescheduled by customer') returning id into v_event_id;
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
  v_agent := public.auto_assign_order(p_order_id, p_actor_user_id, v_previous_agent);
  return v_agent;
end;
$$;

create or replace function public.update_agent_location(p_agent_user_id uuid, p_actor_user_id uuid, p_latitude numeric, p_longitude numeric)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.current_role(p_actor_user_id) <> 'ADMIN' and p_agent_user_id <> p_actor_user_id then raise exception 'Only the agent or an admin can update this location'; end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'Invalid coordinates'; end if;
  update public.agent_profiles set current_latitude = p_latitude, current_longitude = p_longitude, location_updated_at = now() where user_id = p_agent_user_id;
  if not found then raise exception 'Agent profile not found'; end if;
end;
$$;

create or replace function public.update_agent_availability(p_agent_user_id uuid, p_actor_user_id uuid, p_availability public.agent_availability)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.current_role(p_actor_user_id) <> 'ADMIN' and p_agent_user_id <> p_actor_user_id then raise exception 'Only the agent or an admin can update availability'; end if;
  if p_availability = 'AVAILABLE' and exists (select 1 from public.delivery_assignments where agent_id = p_agent_user_id and is_active) then raise exception 'Agent with an active delivery must remain busy'; end if;
  update public.agent_profiles set availability = p_availability where user_id = p_agent_user_id;
  if not found then raise exception 'Agent profile not found'; end if;
end;
$$;
