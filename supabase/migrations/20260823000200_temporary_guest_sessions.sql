-- Temporary browser guest sessions receive ordinary role profiles, but the
-- application deactivates them after their configured expiry without deleting
-- their order history or violating workflow foreign keys.
alter table public.profiles add column guest_expires_at timestamptz;
create index profiles_active_guest_expiry_idx on public.profiles (guest_expires_at)
where guest_expires_at is not null and is_active;
