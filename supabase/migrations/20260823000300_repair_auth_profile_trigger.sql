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
