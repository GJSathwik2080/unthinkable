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
