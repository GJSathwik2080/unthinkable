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
