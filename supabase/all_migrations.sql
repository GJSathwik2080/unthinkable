-- Reset public schema cleanly if running on a new project or retrying
drop schema if exists public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all functions in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all sequences in schema public to postgres, anon, authenticated, service_role;
-- LastMile normalized schema. auth.users is owned by Supabase Auth.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create type public.user_role as enum ('CUSTOMER', 'ADMIN', 'DELIVERY_AGENT');
create type public.agent_availability as enum ('AVAILABLE', 'BUSY', 'OFFLINE');
create type public.order_type as enum ('B2B', 'B2C');
create type public.payment_type as enum ('PREPAID', 'COD');
create type public.order_status as enum ('PLACED', 'ASSIGNED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED', 'RESCHEDULED');
create type public.attempt_status as enum ('SCHEDULED', 'ACTIVE', 'DELIVERED', 'FAILED');
create type public.assignment_method as enum ('AUTO', 'MANUAL', 'RESCHEDULE');
create type public.address_type as enum ('PICKUP', 'DROP');
create type public.notification_channel as enum ('EMAIL', 'SMS');
create type public.notification_status as enum ('PENDING', 'PROCESSING', 'SENT', 'FAILED');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) >= 2),
  phone text,
  role public.user_role not null default 'CUSTOMER',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique check (code ~ '^[A-Z0-9]{2,10}$'),
  is_active boolean not null default true,
  created_by_user_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.service_areas (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones(id),
  name text not null check (char_length(trim(name)) >= 2),
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (zone_id, name),
  check ((latitude is null and longitude is null) or (latitude between -90 and 90 and longitude between -180 and 180))
);

create table public.service_area_postal_codes (
  postal_code text primary key check (postal_code ~ '^[0-9]{6}$'),
  service_area_id uuid not null references public.service_areas(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pricing_settings (
  id boolean primary key default true check (id),
  volumetric_divisor integer not null default 5000 check (volumetric_divisor > 0),
  rounding_grams integer not null default 500 check (rounding_grams > 0),
  currency char(3) not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  updated_by_user_id uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table public.rate_cards (
  id uuid primary key default gen_random_uuid(),
  pickup_zone_id uuid not null references public.zones(id),
  drop_zone_id uuid not null references public.zones(id),
  order_type public.order_type not null,
  base_weight_grams integer not null check (base_weight_grams > 0),
  base_charge_minor integer not null check (base_charge_minor >= 0),
  additional_step_grams integer not null check (additional_step_grams > 0),
  additional_step_charge_minor integer not null check (additional_step_charge_minor >= 0),
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_by_user_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

alter table public.rate_cards add constraint rate_cards_no_overlapping_active_dates
exclude using gist (
  pickup_zone_id with =,
  drop_zone_id with =,
  order_type with =,
  daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
) where (is_active);

create table public.cod_surcharges (
  order_type public.order_type primary key,
  surcharge_minor integer not null check (surcharge_minor >= 0),
  is_active boolean not null default true,
  updated_by_user_id uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table public.agent_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  home_zone_id uuid not null references public.zones(id),
  availability public.agent_availability not null default 'OFFLINE',
  current_latitude numeric(9, 6),
  current_longitude numeric(9, 6),
  location_updated_at timestamptz,
  last_assigned_at timestamptz,
  updated_at timestamptz not null default now(),
  check ((current_latitude is null and current_longitude is null) or (current_latitude between -90 and 90 and current_longitude between -180 and 180))
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  tracking_number text not null unique check (tracking_number ~ '^LM-[A-Z0-9]{8}$'),
  customer_id uuid not null references public.profiles(id),
  created_by_user_id uuid not null references public.profiles(id),
  order_type public.order_type not null,
  payment_type public.payment_type not null,
  current_status public.order_status not null default 'PLACED',
  scheduled_delivery_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_addresses (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  address_type public.address_type not null,
  recipient_name text not null check (char_length(trim(recipient_name)) >= 2),
  recipient_phone text not null check (char_length(trim(recipient_phone)) >= 8),
  address_line_1 text not null check (char_length(trim(address_line_1)) >= 5),
  address_line_2 text,
  service_area_id uuid references public.service_areas(id),
  area_name_snapshot text not null,
  postal_code_snapshot text not null check (postal_code_snapshot ~ '^[0-9]{6}$'),
  zone_id_snapshot uuid not null references public.zones(id),
  created_at timestamptz not null default now(),
  unique (order_id, address_type)
);

create table public.order_pricing_snapshots (
  order_id uuid primary key references public.orders(id) on delete cascade,
  rate_card_id uuid not null references public.rate_cards(id),
  volumetric_divisor integer not null check (volumetric_divisor > 0),
  rounding_grams integer not null check (rounding_grams > 0),
  actual_weight_grams integer not null check (actual_weight_grams > 0),
  volumetric_weight_grams integer not null check (volumetric_weight_grams > 0),
  billable_weight_grams integer not null check (billable_weight_grams > 0),
  base_charge_minor integer not null check (base_charge_minor >= 0),
  additional_charge_minor integer not null check (additional_charge_minor >= 0),
  cod_charge_minor integer not null check (cod_charge_minor >= 0),
  total_charge_minor integer not null check (total_charge_minor >= 0),
  currency char(3) not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  check (billable_weight_grams >= actual_weight_grams and billable_weight_grams >= volumetric_weight_grams),
  check (total_charge_minor = base_charge_minor + additional_charge_minor + cod_charge_minor)
);

create table public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  scheduled_date date,
  status public.attempt_status not null default 'SCHEDULED',
  failure_reason text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, attempt_number),
  check ((status <> 'FAILED') or failure_reason is not null)
);

create table public.delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.delivery_attempts(id) on delete cascade,
  agent_id uuid not null references public.profiles(id),
  assigned_by_user_id uuid references public.profiles(id),
  method public.assignment_method not null,
  is_active boolean not null default true,
  released_at timestamptz,
  release_reason text,
  created_at timestamptz not null default now(),
  check ((is_active and released_at is null) or (not is_active and released_at is not null))
);

create table public.order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status public.order_status not null,
  actor_user_id uuid references public.profiles(id),
  actor_role text not null check (actor_role in ('CUSTOMER', 'ADMIN', 'DELIVERY_AGENT', 'SYSTEM')),
  note text,
  is_override boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  order_event_id uuid not null references public.order_events(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  recipient text not null,
  channel public.notification_channel not null,
  status public.notification_status not null default 'PENDING',
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_message_id text,
  last_error text,
  claimed_at timestamptz,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (order_event_id, channel)
);

create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references public.profiles(id),
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_postal_codes_service_area on public.service_area_postal_codes(service_area_id) where is_active;
create index idx_service_areas_zone on public.service_areas(zone_id) where is_active;
create index idx_orders_customer_created on public.orders(customer_id, created_at desc);
create index idx_orders_status_created on public.orders(current_status, created_at desc);
create index idx_attempts_order_number on public.delivery_attempts(order_id, attempt_number desc);
create index idx_assignments_agent_active on public.delivery_assignments(agent_id) where is_active;
create unique index idx_one_active_agent_assignment on public.delivery_assignments(agent_id) where is_active;
create unique index idx_one_active_assignment_per_attempt on public.delivery_assignments(attempt_id) where is_active;
create index idx_events_order_created on public.order_events(order_id, created_at);
create index idx_outbox_pending on public.notification_outbox(status, next_attempt_at) where status in ('PENDING', 'FAILED');
create index idx_admin_audit_entity on public.admin_audit_log(entity_type, entity_id, created_at desc);

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger zones_set_updated_at before update on public.zones for each row execute function public.set_updated_at();
create trigger areas_set_updated_at before update on public.service_areas for each row execute function public.set_updated_at();
create trigger postal_codes_set_updated_at before update on public.service_area_postal_codes for each row execute function public.set_updated_at();
create trigger rate_cards_set_updated_at before update on public.rate_cards for each row execute function public.set_updated_at();
create trigger agents_set_updated_at before update on public.agent_profiles for each row execute function public.set_updated_at();
create trigger orders_set_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger attempts_set_updated_at before update on public.delivery_attempts for each row execute function public.set_updated_at();

create or replace function public.protect_order_events() returns trigger language plpgsql as $$
begin raise exception 'Order events are append-only'; end;
$$;
create trigger protect_order_events before update or delete on public.order_events for each row execute function public.protect_order_events();

create or replace function public.protect_order_snapshots() returns trigger language plpgsql as $$
begin raise exception 'Order address and pricing snapshots are immutable'; end;
$$;
create trigger protect_order_addresses before update or delete on public.order_addresses for each row execute function public.protect_order_snapshots();
create trigger protect_order_pricing before update or delete on public.order_pricing_snapshots for each row execute function public.protect_order_snapshots();

create or replace function public.handle_new_customer() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'New customer'), nullif(new.raw_user_meta_data ->> 'phone', ''), 'CUSTOMER')
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_customer();
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
-- Browser clients can read only the records authorized by role/ownership.
alter table public.profiles enable row level security;
alter table public.zones enable row level security;
alter table public.service_areas enable row level security;
alter table public.service_area_postal_codes enable row level security;
alter table public.pricing_settings enable row level security;
alter table public.rate_cards enable row level security;
alter table public.cod_surcharges enable row level security;
alter table public.agent_profiles enable row level security;
alter table public.orders enable row level security;
alter table public.order_addresses enable row level security;
alter table public.order_pricing_snapshots enable row level security;
alter table public.delivery_attempts enable row level security;
alter table public.delivery_assignments enable row level security;
alter table public.order_events enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.admin_audit_log enable row level security;

create policy "profiles: own or admin" on public.profiles for select to authenticated using (
  id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "zones: authenticated read" on public.zones for select to authenticated using (
  is_active or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "areas: authenticated read" on public.service_areas for select to authenticated using (
  is_active or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "postal codes: authenticated read" on public.service_area_postal_codes for select to authenticated using (
  is_active or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "pricing settings: authenticated read" on public.pricing_settings for select to authenticated using (true);
create policy "rate cards: authenticated read" on public.rate_cards for select to authenticated using (
  is_active or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "cod surcharge: authenticated read" on public.cod_surcharges for select to authenticated using (
  is_active or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "agent profile: own or admin" on public.agent_profiles for select to authenticated using (
  user_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN'
);
create policy "orders: owner agent or admin" on public.orders for select to authenticated using (
  customer_id = auth.uid()
  or public.current_role(auth.uid()) = 'ADMIN'
  or exists (select 1 from public.delivery_assignments a where a.agent_id = auth.uid() and a.attempt_id in (select da.id from public.delivery_attempts da where da.order_id = orders.id))
);
create policy "addresses: authorized order viewer" on public.order_addresses for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_addresses.order_id and (o.customer_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN' or exists (select 1 from public.delivery_assignments a join public.delivery_attempts da on da.id = a.attempt_id where da.order_id = o.id and a.agent_id = auth.uid())))
);
create policy "pricing: authorized order viewer" on public.order_pricing_snapshots for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_pricing_snapshots.order_id and (o.customer_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN' or exists (select 1 from public.delivery_assignments a join public.delivery_attempts da on da.id = a.attempt_id where da.order_id = o.id and a.agent_id = auth.uid())))
);
create policy "attempts: authorized order viewer" on public.delivery_attempts for select to authenticated using (
  exists (select 1 from public.orders o where o.id = delivery_attempts.order_id and (o.customer_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN' or exists (select 1 from public.delivery_assignments a where a.attempt_id = delivery_attempts.id and a.agent_id = auth.uid())))
);
create policy "assignments: agent or admin" on public.delivery_assignments for select to authenticated using (
  agent_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN'
  or exists (select 1 from public.delivery_attempts da join public.orders o on o.id = da.order_id where da.id = delivery_assignments.attempt_id and o.customer_id = auth.uid())
);
create policy "events: authorized order viewer" on public.order_events for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_events.order_id and (o.customer_id = auth.uid() or public.current_role(auth.uid()) = 'ADMIN' or exists (select 1 from public.delivery_assignments a join public.delivery_attempts da on da.id = a.attempt_id where da.order_id = o.id and a.agent_id = auth.uid())))
);
create policy "outbox: admin only" on public.notification_outbox for select to authenticated using (public.current_role(auth.uid()) = 'ADMIN');
create policy "audit: admin only" on public.admin_audit_log for select to authenticated using (public.current_role(auth.uid()) = 'ADMIN');

-- No browser INSERT/UPDATE/DELETE policies are created. Next.js uses service_role only after its own auth checks.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.calculate_order_quote(text, text, numeric, numeric, numeric, numeric, public.order_type, public.payment_type) to service_role;
grant execute on function public.create_order(uuid, uuid, jsonb, date) to service_role;
grant execute on function public.auto_assign_order(uuid, uuid, uuid) to service_role;
grant execute on function public.assign_order_manually(uuid, uuid, uuid) to service_role;
grant execute on function public.transition_order_status(uuid, public.order_status, uuid, text, text, boolean) to service_role;
grant execute on function public.reschedule_failed_order(uuid, uuid, date) to service_role;
grant execute on function public.update_agent_location(uuid, uuid, numeric, numeric) to service_role;
grant execute on function public.update_agent_availability(uuid, uuid, public.agent_availability) to service_role;
grant execute on function public.current_role(uuid) to authenticated;
-- Development configuration data. Replace values through Admin screens in production.
insert into public.pricing_settings (id, volumetric_divisor, rounding_grams, currency)
values (true, 5000, 500, 'INR')
on conflict (id) do update set volumetric_divisor = excluded.volumetric_divisor, rounding_grams = excluded.rounding_grams, updated_at = now();

insert into public.zones (name, code) values
  ('Chennai Central', 'CC'),
  ('Chennai South', 'CS'),
  ('Chennai West', 'CW'),
  ('Universal service', 'UNIV')
on conflict (code) do update set name = excluded.name, is_active = true;

insert into public.service_areas (zone_id, name, latitude, longitude)
select z.id, values_list.name, values_list.latitude, values_list.longitude
from (values
  ('CC', 'Parrys', 13.087800::numeric, 80.288200::numeric),
  ('CC', 'George Town', 13.092000::numeric, 80.285100::numeric),
  ('CS', 'Velachery', 12.981500::numeric, 80.218000::numeric),
  ('CS', 'T Nagar', 13.041800::numeric, 80.234100::numeric),
  ('CW', 'Ambattur', 13.114300::numeric, 80.154800::numeric),
  ('UNIV', 'Universal coverage', null::numeric, null::numeric)
) as values_list(zone_code, name, latitude, longitude)
join public.zones z on z.code = values_list.zone_code
on conflict (zone_id, name) do update set latitude = excluded.latitude, longitude = excluded.longitude, is_active = true;

insert into public.service_area_postal_codes (postal_code, service_area_id)
select values_list.postal_code, a.id
from (values
  ('600001', 'CC', 'Parrys'),
  ('600002', 'CC', 'George Town'),
  ('600041', 'CS', 'Velachery'),
  ('600042', 'CS', 'T Nagar'),
  ('600096', 'CW', 'Ambattur')
) as values_list(postal_code, zone_code, area_name)
join public.zones z on z.code = values_list.zone_code
join public.service_areas a on a.zone_id = z.id and a.name = values_list.area_name
on conflict (postal_code) do update set service_area_id = excluded.service_area_id, is_active = true;

insert into public.rate_cards (pickup_zone_id, drop_zone_id, order_type, base_weight_grams, base_charge_minor, additional_step_grams, additional_step_charge_minor, effective_from)
select
  pickup.id,
  drop_zone.id,
  order_types.order_type::public.order_type,
  1000,
  case
    when pickup.id = drop_zone.id and order_types.order_type = 'B2B' then 6500
    when pickup.id = drop_zone.id then 8000
    when order_types.order_type = 'B2B' then 10500
    else 13500
  end,
  500,
  case
    when pickup.id = drop_zone.id and order_types.order_type = 'B2B' then 1800
    when pickup.id = drop_zone.id then 2400
    when order_types.order_type = 'B2B' then 3000
    else 3600
  end,
  date '2026-01-01'
from public.zones pickup
cross join public.zones drop_zone
cross join (values ('B2B'), ('B2C')) as order_types(order_type)
where pickup.is_active and drop_zone.is_active
on conflict do nothing;

insert into public.cod_surcharges (order_type, surcharge_minor)
values ('B2B', 2500), ('B2C', 3500)
on conflict (order_type) do update set surcharge_minor = excluded.surcharge_minor, is_active = true, updated_at = now();
-- Strengthen cross-portal authorization and preserve workflow-table invariants.

create or replace function public.is_admin(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.is_active and p.role = 'ADMIN'
  );
$$;

create or replace function public.can_view_order(p_order_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and (
        o.customer_id = p_user_id
        or public.is_admin(p_user_id)
        or exists (
          select 1
          from public.delivery_attempts da
          join public.delivery_assignments a on a.attempt_id = da.id
          where da.order_id = o.id and a.agent_id = p_user_id
        )
      )
  );
$$;

create or replace function public.can_view_attempt(p_attempt_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select public.can_view_order(da.order_id, p_user_id)
  from public.delivery_attempts da
  where da.id = p_attempt_id;
$$;

create or replace function public.assert_agent_profile_role()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.current_role(new.user_id) <> 'DELIVERY_AGENT' then
    raise exception 'Agent profiles require a DELIVERY_AGENT profile role';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_agent_role_demotion()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'DELIVERY_AGENT' and new.role <> 'DELIVERY_AGENT'
     and exists (select 1 from public.agent_profiles ap where ap.user_id = old.id) then
    raise exception 'Remove the agent profile before changing a delivery-agent role';
  end if;
  return new;
end;
$$;

create trigger agent_profiles_require_delivery_agent
before insert or update of user_id on public.agent_profiles
for each row execute function public.assert_agent_profile_role();

create trigger profiles_prevent_agent_role_demotion
before update of role on public.profiles
for each row execute function public.prevent_agent_role_demotion();

alter table public.delivery_assignments
  add constraint delivery_assignments_agent_profile_fkey
  foreign key (agent_id) references public.agent_profiles(user_id);

drop policy "orders: owner agent or admin" on public.orders;
drop policy "addresses: authorized order viewer" on public.order_addresses;
drop policy "pricing: authorized order viewer" on public.order_pricing_snapshots;
drop policy "attempts: authorized order viewer" on public.delivery_attempts;
drop policy "assignments: agent or admin" on public.delivery_assignments;
drop policy "events: authorized order viewer" on public.order_events;

create policy "orders: authorized viewer" on public.orders for select to authenticated using (
  public.can_view_order(id, auth.uid())
);
create policy "addresses: authorized order viewer" on public.order_addresses for select to authenticated using (
  public.can_view_order(order_id, auth.uid())
);
create policy "pricing: authorized order viewer" on public.order_pricing_snapshots for select to authenticated using (
  public.can_view_order(order_id, auth.uid())
);
create policy "attempts: authorized order viewer" on public.delivery_attempts for select to authenticated using (
  public.can_view_order(order_id, auth.uid())
);
create policy "assignments: authorized order viewer" on public.delivery_assignments for select to authenticated using (
  public.can_view_attempt(attempt_id, auth.uid())
);
create policy "events: authorized order viewer" on public.order_events for select to authenticated using (
  public.can_view_order(order_id, auth.uid())
);

create or replace function public.assign_order_manually(p_order_id uuid, p_agent_id uuid, p_actor_user_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_attempt_id uuid; v_event_id uuid;
begin
  if public.current_role(p_actor_user_id) <> 'ADMIN' then
    raise exception 'Only an admin can manually assign an order';
  end if;
  select id into v_attempt_id from public.delivery_attempts where order_id = p_order_id and status = 'SCHEDULED' order by attempt_number desc limit 1 for update;
  if v_attempt_id is null then raise exception 'Order has no scheduled attempt available for assignment'; end if;
  perform 1 from public.agent_profiles ap where ap.user_id = p_agent_id and ap.availability = 'AVAILABLE' for update;
  if not found or exists (select 1 from public.delivery_assignments where agent_id = p_agent_id and is_active) then raise exception 'Selected agent is not eligible'; end if;
  insert into public.delivery_assignments (attempt_id, agent_id, assigned_by_user_id, method) values (v_attempt_id, p_agent_id, p_actor_user_id, 'MANUAL');
  update public.delivery_attempts set status = 'ACTIVE' where id = v_attempt_id;
  update public.agent_profiles set availability = 'BUSY', last_assigned_at = now() where user_id = p_agent_id;
  update public.orders set current_status = 'ASSIGNED' where id = p_order_id;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (p_order_id, 'ASSIGNED', p_actor_user_id, 'ADMIN', 'Agent assigned manually') returning id into v_event_id;
  insert into public.admin_audit_log (actor_user_id, entity_type, entity_id, action, metadata)
  values (p_actor_user_id, 'ORDER', p_order_id, 'MANUAL_ASSIGNMENT', jsonb_build_object('attemptId', v_attempt_id, 'agentId', p_agent_id));
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
  select da.id, a.agent_id into v_attempt_id, v_agent_id
  from public.delivery_attempts da join public.delivery_assignments a on a.attempt_id = da.id and a.is_active
  where da.order_id = p_order_id and da.status = 'ACTIVE'
  order by da.attempt_number desc limit 1 for update;

  if v_role = 'DELIVERY_AGENT' and v_agent_id is distinct from p_actor_user_id then raise exception 'Agent is not assigned to this order'; end if;
  if v_role = 'CUSTOMER' then raise exception 'Customers cannot change delivery status'; end if;
  if p_is_override and v_role <> 'ADMIN' then raise exception 'Only an admin can override delivery status'; end if;
  if p_is_override and (p_next_status in ('PLACED', 'RESCHEDULED') or coalesce(trim(p_note), '') = '') then
    raise exception 'Use the create or reschedule workflow for this status; overrides require a reason';
  end if;
  if p_next_status in ('ASSIGNED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED') and v_attempt_id is null then
    raise exception 'This status requires an active delivery attempt and assignment';
  end if;

  v_valid := (v_current = 'ASSIGNED' and p_next_status in ('PICKED_UP', 'FAILED')) or
             (v_current = 'PICKED_UP' and p_next_status in ('IN_TRANSIT', 'FAILED')) or
             (v_current = 'IN_TRANSIT' and p_next_status in ('OUT_FOR_DELIVERY', 'FAILED')) or
             (v_current = 'OUT_FOR_DELIVERY' and p_next_status in ('DELIVERED', 'FAILED'));
  if not v_valid and not p_is_override then raise exception 'Invalid status transition'; end if;
  if p_next_status = 'FAILED' and coalesce(trim(p_failure_reason), '') = '' then raise exception 'Failed delivery requires a reason'; end if;

  update public.orders set current_status = p_next_status where id = p_order_id;
  if p_next_status in ('PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY') then
    update public.delivery_attempts set started_at = coalesce(started_at, now()) where id = v_attempt_id;
  end if;
  if p_next_status = 'DELIVERED' then
    update public.delivery_attempts set status = 'DELIVERED', completed_at = now() where id = v_attempt_id;
    update public.delivery_assignments set is_active = false, released_at = now(), release_reason = 'Delivered' where attempt_id = v_attempt_id and is_active;
    update public.agent_profiles set availability = 'AVAILABLE' where user_id = v_agent_id;
  elsif p_next_status = 'FAILED' then
    update public.delivery_attempts set status = 'FAILED', failure_reason = p_failure_reason, completed_at = now() where id = v_attempt_id;
    update public.delivery_assignments set is_active = false, released_at = now(), release_reason = 'Delivery failed' where attempt_id = v_attempt_id and is_active;
    update public.agent_profiles set availability = 'AVAILABLE' where user_id = v_agent_id;
  end if;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note, is_override)
  values (p_order_id, p_next_status, p_actor_user_id, v_role::text, coalesce(p_failure_reason, p_note), p_is_override)
  returning id into v_event_id;
  if p_is_override then
    insert into public.admin_audit_log (actor_user_id, entity_type, entity_id, action, metadata)
    values (p_actor_user_id, 'ORDER', p_order_id, 'STATUS_OVERRIDE', jsonb_build_object('fromStatus', v_current, 'toStatus', p_next_status, 'reason', p_note));
  end if;
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
end;
$$;

grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.can_view_order(uuid, uuid) to authenticated;
grant execute on function public.can_view_attempt(uuid, uuid) to authenticated;
-- Temporary browser guest sessions receive ordinary role profiles, but the
-- application deactivates them after their configured expiry without deleting
-- their order history or violating workflow foreign keys.
alter table public.profiles add column guest_expires_at timestamptz;
create index profiles_active_guest_expiry_idx on public.profiles (guest_expires_at)
where guest_expires_at is not null and is_active;
-- Repair the Auth-user profile trigger for projects that applied the first
-- migration before the hardened trigger definition was introduced.
create or replace function public.handle_new_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'New customer'),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    'CUSTOMER'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
-- A valid six-digit postal code can be quoted without a preconfigured postal
-- mapping. Known mappings still determine their configured zone; unknown
-- codes use the universal service zone and its live rate cards.
insert into public.zones (name, code)
values ('Universal service', 'UNIV')
on conflict (code) do update set name = excluded.name, is_active = true;

insert into public.service_areas (zone_id, name, latitude, longitude)
select id, 'Universal coverage', null, null from public.zones where code = 'UNIV'
on conflict (zone_id, name) do update set is_active = true;

insert into public.rate_cards (pickup_zone_id, drop_zone_id, order_type, base_weight_grams, base_charge_minor, additional_step_grams, additional_step_charge_minor, effective_from)
select
  pickup.id,
  drop_zone.id,
  order_types.order_type::public.order_type,
  1000,
  case
    when pickup.id = drop_zone.id and order_types.order_type = 'B2B' then 6500
    when pickup.id = drop_zone.id then 8000
    when order_types.order_type = 'B2B' then 10500
    else 13500
  end,
  500,
  case
    when pickup.id = drop_zone.id and order_types.order_type = 'B2B' then 1800
    when pickup.id = drop_zone.id then 2400
    when order_types.order_type = 'B2B' then 3000
    else 3600
  end,
  date '2026-01-01'
from public.zones pickup
cross join public.zones drop_zone
cross join (values ('B2B'), ('B2C')) as order_types(order_type)
where pickup.is_active and drop_zone.is_active
on conflict do nothing;

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
  if coalesce(trim(p_pickup_postal_code), '') !~ '^[0-9]{6}$' or coalesce(trim(p_drop_postal_code), '') !~ '^[0-9]{6}$' then
    raise exception 'Enter valid 6-digit postal codes';
  end if;
  if p_length_cm <= 0 or p_breadth_cm <= 0 or p_height_cm <= 0 or p_actual_weight_kg <= 0 then
    raise exception 'Package dimensions and actual weight must be greater than zero';
  end if;

  select a.id as area_id, a.name as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
  into v_pickup
  from public.service_area_postal_codes pc
  join public.service_areas a on a.id = pc.service_area_id and a.is_active
  join public.zones z on z.id = a.zone_id and z.is_active
  where pc.postal_code = trim(p_pickup_postal_code) and pc.is_active;
  if not found then
    select a.id as area_id, ('Postal code ' || trim(p_pickup_postal_code))::text as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
    into v_pickup
    from public.service_areas a join public.zones z on z.id = a.zone_id and z.is_active
    where z.code = 'UNIV' and a.name = 'Universal coverage' and a.is_active;
    if not found then raise exception 'Universal postal-code coverage is not configured'; end if;
  end if;

  select a.id as area_id, a.name as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
  into v_drop
  from public.service_area_postal_codes pc
  join public.service_areas a on a.id = pc.service_area_id and a.is_active
  join public.zones z on z.id = a.zone_id and z.is_active
  where pc.postal_code = trim(p_drop_postal_code) and pc.is_active;
  if not found then
    select a.id as area_id, ('Postal code ' || trim(p_drop_postal_code))::text as area_name, z.id as zone_id, z.name as zone_name, a.latitude, a.longitude
    into v_drop
    from public.service_areas a join public.zones z on z.id = a.zone_id and z.is_active
    where z.code = 'UNIV' and a.name = 'Universal coverage' and a.is_active;
    if not found then raise exception 'Universal postal-code coverage is not configured'; end if;
  end if;

  select * into v_settings from public.pricing_settings where id = true;
  if not found then raise exception 'Pricing settings are unavailable'; end if;
  select * into v_rate from public.rate_cards
  where pickup_zone_id = v_pickup.zone_id and drop_zone_id = v_drop.zone_id and order_type = p_order_type and is_active
    and effective_from <= current_date and (effective_to is null or effective_to >= current_date)
  order by effective_from desc limit 1;
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
-- Some projects retain an incorrectly owned or stale Auth trigger after an
-- earlier schema attempt. Recreate it so Auth can insert a public profile.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_customer();

create function public.handle_new_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'New customer'),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    'CUSTOMER'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

alter function public.handle_new_customer() owner to postgres;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_customer();
-- Create public profiles from the application after Auth succeeds. This avoids
-- a broken auth.users trigger preventing all account and guest creation.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_customer();
-- Keep shipment entry simple: a name and address only need to be present.
-- Phone numbers remain normalized and validated by the application as 10 digits.
alter table public.order_addresses
  drop constraint if exists order_addresses_recipient_name_check,
  drop constraint if exists order_addresses_address_line_1_check;

alter table public.order_addresses
  add constraint order_addresses_recipient_name_check check (char_length(trim(recipient_name)) >= 1),
  add constraint order_addresses_address_line_1_check check (char_length(trim(address_line_1)) >= 1);


-- Grant full table, sequence, and function access to Supabase roles
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on all tables in schema public to postgres, anon, authenticated, service_role;
grant all on all functions in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;
