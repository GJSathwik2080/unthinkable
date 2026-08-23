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
