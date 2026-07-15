-- Restrict public.stations to read-only application access.
-- Existing station rows, keys, column types, and service/admin roles are unchanged.
-- Manual rollback: use a separately reviewed migration to remove the read policy
-- and make an explicit RLS decision; do not re-grant client write privileges.

revoke insert, update, delete, truncate, references, trigger
  on table public.stations
  from anon, authenticated;

grant select
  on table public.stations
  to anon, authenticated;

alter table public.stations enable row level security;

drop policy if exists "stations_public_read" on public.stations;

create policy "stations_public_read"
  on public.stations
  for select
  to anon, authenticated
  using (true);
