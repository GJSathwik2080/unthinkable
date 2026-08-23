-- Create public profiles from the application after Auth succeeds. This avoids
-- a broken auth.users trigger preventing all account and guest creation.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_customer();
