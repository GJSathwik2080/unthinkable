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

  insert into public.delivery_assignments (attempt_id, agent_id, assigned_by_user_id, method) values (v_attempt_id, v_agent_id, p_actor_user_id, (case when p_excluded_agent_id is null then 'AUTO' else 'RESCHEDULE' end)::public.assignment_method);
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
  if public.current_role(p_actor_user_id) <> 'ADMIN' then
    raise exception 'Only an admin can manually assign an order';
  end if;
  select id into v_attempt_id from public.delivery_attempts where order_id = p_order_id and status = 'SCHEDULED' order by attempt_number desc limit 1 for update;
  if v_attempt_id is null then raise exception 'Order has no scheduled attempt available for assignment'; end if;
  perform 1 from public.agent_profiles ap where ap.user_id = p_agent_id and ap.availability = 'AVAILABLE' for update;
  if not found or exists (select 1 from public.delivery_assignments where agent_id = p_agent_id and is_active) then raise exception 'Selected agent is not eligible'; end if;
  insert into public.delivery_assignments (attempt_id, agent_id, assigned_by_user_id, method) values (v_attempt_id, p_agent_id, p_actor_user_id, 'MANUAL'::public.assignment_method);
  update public.delivery_attempts set status = 'ACTIVE' where id = v_attempt_id;
  update public.agent_profiles set availability = 'BUSY', last_assigned_at = now() where user_id = p_agent_id;
  update public.orders set current_status = 'ASSIGNED' where id = p_order_id;
  insert into public.order_events (order_id, status, actor_user_id, actor_role, note) values (p_order_id, 'ASSIGNED', p_actor_user_id, 'ADMIN', 'Agent assigned manually') returning id into v_event_id;
  insert into public.admin_audit_log (actor_user_id, entity_type, entity_id, action, metadata)
  values (p_actor_user_id, 'ORDER', p_order_id, 'MANUAL_ASSIGNMENT', jsonb_build_object('attemptId', v_attempt_id, 'agentId', p_agent_id));
  perform public.enqueue_status_notifications(v_event_id, p_order_id);
end;
$$;
