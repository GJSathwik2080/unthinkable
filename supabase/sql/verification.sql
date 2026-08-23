-- Run each statement individually in Supabase SQL Editor after applying migrations.
select table_name from information_schema.tables where table_schema = 'public' order by table_name;

select pc.postal_code, a.name as area_name, z.code as zone_code
from public.service_area_postal_codes pc
join public.service_areas a on a.id = pc.service_area_id
join public.zones z on z.id = a.zone_id
order by pc.postal_code;

select order_type, count(*) as active_rate_cards
from public.rate_cards where is_active group by order_type order by order_type;

select public.calculate_order_quote('600001', '600041', 40, 30, 20, 3.0, 'B2C', 'COD');

select indexname, indexdef from pg_indexes where tablename = 'delivery_assignments' and indexname = 'idx_one_active_agent_assignment';

-- The authorization policies use security-definer helpers instead of querying
-- protected workflow tables inside one another's RLS predicates.
select tablename, policyname, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('orders', 'order_addresses', 'order_pricing_snapshots', 'delivery_attempts', 'delivery_assignments', 'order_events')
order by tablename, policyname;

-- Both constraints must be present: a delivery assignment may only reference
-- a delivery-agent profile, and an agent can have at most one active assignment.
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.delivery_assignments'::regclass
  and conname = 'delivery_assignments_agent_profile_fkey';

-- These checks should return zero rows after the integrity migration.
select p.id, p.role
from public.agent_profiles ap
join public.profiles p on p.id = ap.user_id
where p.role <> 'DELIVERY_AGENT';

select o.id, o.tracking_number, o.current_status, da.id as active_attempt_id, a.id as active_assignment_id
from public.orders o
left join public.delivery_attempts da on da.order_id = o.id and da.status = 'ACTIVE'
left join public.delivery_assignments a on a.attempt_id = da.id and a.is_active
where o.current_status in ('ASSIGNED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY')
  and (da.id is null or a.id is null);

select o.id, o.tracking_number, o.current_status
from public.orders o
where o.current_status in ('DELIVERED', 'FAILED')
  and exists (
    select 1
    from public.delivery_attempts da
    left join public.delivery_assignments a on a.attempt_id = da.id and a.is_active
    where da.order_id = o.id and (da.status = 'ACTIVE' or a.id is not null)
  );

-- The append-only and immutable snapshot triggers remain installed.
select tgrelid::regclass as table_name, tgname
from pg_trigger
where not tgisinternal
  and tgname in ('protect_order_events', 'protect_order_addresses', 'protect_order_pricing')
order by tgname;
