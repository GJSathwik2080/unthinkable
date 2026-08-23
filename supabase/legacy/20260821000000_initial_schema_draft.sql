-- LastMile: application schema. Supabase Auth owns auth.users.
create type public.user_role as enum ('CUSTOMER', 'ADMIN', 'DELIVERY_AGENT');
create type public.agent_availability as enum ('AVAILABLE', 'BUSY', 'OFFLINE');
create type public.order_type as enum ('B2B', 'B2C');
create type public.payment_type as enum ('PREPAID', 'COD');
create type public.movement_type as enum ('INTRA_ZONE', 'INTER_ZONE');
create type public.order_status as enum ('PLACED', 'ASSIGNED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED', 'RESCHEDULED');
create type public.attempt_status as enum ('ACTIVE', 'DELIVERED', 'FAILED', 'SCHEDULED');
create type public.notification_channel as enum ('EMAIL', 'SMS');
create type public.notification_status as enum ('PENDING', 'SENT', 'FAILED');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.user_role not null default 'CUSTOMER',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.zone_areas (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones(id),
  area_name text not null,
  postal_code text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (postal_code, area_name)
);

create table public.pricing_settings (
  id boolean primary key default true check (id),
  volumetric_divisor integer not null default 5000 check (volumetric_divisor > 0),
  rounding_grams integer not null default 500 check (rounding_grams > 0),
  currency char(3) not null default 'INR',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table public.rate_cards (
  id uuid primary key default gen_random_uuid(),
  pickup_zone_id uuid not null references public.zones(id),
  drop_zone_id uuid not null references public.zones(id),
  movement_type public.movement_type not null,
  order_type public.order_type not null,
  base_weight_grams integer not null check (base_weight_grams > 0),
  base_charge_minor integer not null check (base_charge_minor >= 0),
  additional_step_grams integer not null check (additional_step_grams > 0),
  additional_step_charge_minor integer not null check (additional_step_charge_minor >= 0),
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((movement_type = 'INTRA_ZONE' and pickup_zone_id = drop_zone_id) or (movement_type = 'INTER_ZONE' and pickup_zone_id <> drop_zone_id)),
  check (effective_to is null or effective_to >= effective_from)
);

create table public.cod_surcharges (
  id uuid primary key default gen_random_uuid(),
  order_type public.order_type not null unique,
  surcharge_minor integer not null check (surcharge_minor >= 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table public.agent_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  home_zone_id uuid not null references public.zones(id),
  availability public.agent_availability not null default 'OFFLINE',
  current_latitude numeric(9,6),
  current_longitude numeric(9,6),
  location_updated_at timestamptz,
  last_assigned_at timestamptz,
  updated_at timestamptz not null default now(),
  check ((current_latitude is null and current_longitude is null) or (current_latitude between -90 and 90 and current_longitude between -180 and 180))
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  tracking_number text not null unique,
  customer_id uuid not null references public.profiles(id),
  created_by_user_id uuid not null references public.profiles(id),
  pickup_name text not null, pickup_phone text not null, pickup_address text not null, pickup_area text not null, pickup_postal_code text not null,
  drop_name text not null, drop_phone text not null, drop_address text not null, drop_area text not null, drop_postal_code text not null,
  pickup_zone_id uuid not null references public.zones(id), drop_zone_id uuid not null references public.zones(id),
  length_cm numeric(8,2) not null check (length_cm > 0), breadth_cm numeric(8,2) not null check (breadth_cm > 0), height_cm numeric(8,2) not null check (height_cm > 0),
  actual_weight_grams integer not null check (actual_weight_grams > 0), volumetric_weight_grams integer not null check (volumetric_weight_grams > 0), billable_weight_grams integer not null check (billable_weight_grams > 0),
  order_type public.order_type not null, payment_type public.payment_type not null, movement_type public.movement_type not null,
  rate_card_id uuid not null references public.rate_cards(id), base_charge_minor integer not null, additional_charge_minor integer not null, cod_charge_minor integer not null, total_charge_minor integer not null, currency char(3) not null default 'INR',
  current_status public.order_status not null default 'PLACED', assigned_agent_id uuid references public.profiles(id), scheduled_delivery_date date,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (total_charge_minor = base_charge_minor + additional_charge_minor + cod_charge_minor)
);

create table public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  attempt_number integer not null check (attempt_number > 0),
  agent_id uuid references public.profiles(id),
  scheduled_date date,
  status public.attempt_status not null default 'SCHEDULED',
  failure_reason text,
  assigned_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (order_id, attempt_number)
);

create table public.order_tracking_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  status public.order_status not null,
  actor_user_id uuid references public.profiles(id),
  actor_role text not null default 'SYSTEM',
  note text,
  is_override boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  tracking_event_id uuid not null references public.order_tracking_events(id),
  order_id uuid not null references public.orders(id),
  recipient text not null,
  channel public.notification_channel not null,
  status public.notification_status not null default 'PENDING',
  attempt_count integer not null default 0,
  provider_message_id text,
  last_error text,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tracking_event_id, channel)
);

create index idx_zone_areas_postal_code on public.zone_areas(postal_code) where is_active;
create index idx_orders_customer_created on public.orders(customer_id, created_at desc);
create index idx_orders_status_created on public.orders(current_status, created_at desc);
create index idx_orders_pickup_zone_status on public.orders(pickup_zone_id, current_status);
create index idx_orders_agent_status on public.orders(assigned_agent_id, current_status);
create index idx_rate_cards_lookup on public.rate_cards(pickup_zone_id, drop_zone_id, order_type, effective_from desc) where is_active;
create index idx_tracking_events_order_created on public.order_tracking_events(order_id, created_at);
create index idx_notification_outbox_pending on public.notification_outbox(status, next_attempt_at);
create unique index idx_one_active_attempt_per_agent on public.delivery_attempts(agent_id) where status = 'ACTIVE' and agent_id is not null;

create or replace function public.protect_tracking_events() returns trigger language plpgsql as $$
begin raise exception 'Tracking history is append-only'; end; $$;
create trigger protect_tracking_events before update or delete on public.order_tracking_events for each row execute function public.protect_tracking_events();

create or replace function public.handle_new_customer() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles (id, full_name, role) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', 'New customer'), 'CUSTOMER'); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_customer();

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path = public as $$ select role from public.profiles where id = auth.uid() $$;

alter table public.profiles enable row level security;
alter table public.zones enable row level security;
alter table public.zone_areas enable row level security;
alter table public.pricing_settings enable row level security;
alter table public.rate_cards enable row level security;
alter table public.cod_surcharges enable row level security;
alter table public.agent_profiles enable row level security;
alter table public.orders enable row level security;
alter table public.delivery_attempts enable row level security;
alter table public.order_tracking_events enable row level security;
alter table public.notification_outbox enable row level security;

create policy "profiles: own or admin" on public.profiles for select using (id = auth.uid() or public.current_role() = 'ADMIN');
create policy "zones: authenticated read" on public.zones for select to authenticated using (is_active or public.current_role() = 'ADMIN');
create policy "areas: authenticated read" on public.zone_areas for select to authenticated using (is_active or public.current_role() = 'ADMIN');
create policy "rates: authenticated read" on public.rate_cards for select to authenticated using (is_active or public.current_role() = 'ADMIN');
create policy "cod: authenticated read" on public.cod_surcharges for select to authenticated using (is_active or public.current_role() = 'ADMIN');
create policy "orders: customer, agent, or admin read" on public.orders for select using (customer_id = auth.uid() or assigned_agent_id = auth.uid() or public.current_role() = 'ADMIN');
create policy "attempts: customer, agent, or admin read" on public.delivery_attempts for select using (exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or o.assigned_agent_id = auth.uid() or public.current_role() = 'ADMIN')));
create policy "events: customer, agent, or admin read" on public.order_tracking_events for select using (exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or o.assigned_agent_id = auth.uid() or public.current_role() = 'ADMIN')));
