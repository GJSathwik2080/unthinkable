update public.profiles 
set role = 'ADMIN' 
where id = 'a165011a-d6ef-48c7-8128-a808c47161b5';

update public.profiles 
set role = 'DELIVERY_AGENT' 
where id = '5efd533c-7ad6-41da-96f3-8b238df6ea49';

insert into public.agent_profiles (user_id, home_zone_id, availability)
select 
  '5efd533c-7ad6-41da-96f3-8b238df6ea49'::uuid, 
  z.id, 
  'AVAILABLE'
from public.zones z 
where z.code = 'CC'
limit 1
on conflict (user_id) do update 
set home_zone_id = excluded.home_zone_id, 
    availability = excluded.availability;