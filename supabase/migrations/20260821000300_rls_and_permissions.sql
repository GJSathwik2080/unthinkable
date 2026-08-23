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
