-- AIFishMap Sprint 7.13: per-user favourite water stations.

create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  station_id text not null,
  created_at timestamptz not null default now(),
  unique (user_id, station_id)
);

create unique index if not exists favorites_user_station_idx
  on public.favorites (user_id, station_id);

create index if not exists favorites_user_created_at_idx
  on public.favorites (user_id, created_at desc);

alter table public.favorites enable row level security;

drop policy if exists "favorites_owner_read" on public.favorites;
create policy "favorites_owner_read" on public.favorites
for select to authenticated using (auth.uid() = user_id);

drop policy if exists "favorites_owner_insert" on public.favorites;
create policy "favorites_owner_insert" on public.favorites
for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "favorites_owner_update" on public.favorites;

drop policy if exists "favorites_owner_delete" on public.favorites;
create policy "favorites_owner_delete" on public.favorites
for delete to authenticated using (auth.uid() = user_id);

revoke all on public.favorites from anon;
revoke update on public.favorites from authenticated;
grant select, insert, delete on public.favorites to authenticated;
