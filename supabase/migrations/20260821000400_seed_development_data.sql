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
