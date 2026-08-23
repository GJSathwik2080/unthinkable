-- Some projects retain an incorrectly owned or stale Auth trigger after an
-- earlier schema attempt. Recreate it so Auth can insert a public profile.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_customer();

create function public.handle_new_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
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

alter function public.handle_new_customer() owner to postgres;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_customer();
