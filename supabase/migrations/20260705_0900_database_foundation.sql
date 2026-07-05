-- AIFishMap database foundation.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  full_name text,
  avatar text,
  avatar_url text,
  country text,
  reputation integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists id uuid references auth.users(id) on delete cascade;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists avatar text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists country text;
alter table public.profiles add column if not exists reputation integer not null default 0;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();
create unique index if not exists profiles_id_unique_idx on public.profiles (id);

create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  station_id text not null,
  created_at timestamptz not null default now(),
  unique (user_id, station_id)
);

alter table public.favorites add column if not exists id uuid default gen_random_uuid();
alter table public.favorites add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.favorites add column if not exists station_id text;
alter table public.favorites add column if not exists created_at timestamptz not null default now();
create unique index if not exists favorites_user_station_idx
  on public.favorites (user_id, station_id);
create unique index if not exists favorites_id_unique_idx on public.favorites (id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  category text,
  description text,
  image_url text,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  still_valid_count integer not null default 0,
  no_longer_valid_count integer not null default 0
);

alter table public.reports add column if not exists id uuid default gen_random_uuid();
alter table public.reports add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.reports add column if not exists type text;
alter table public.reports add column if not exists category text;
alter table public.reports add column if not exists description text;
alter table public.reports add column if not exists image_url text;
alter table public.reports add column if not exists latitude double precision;
alter table public.reports add column if not exists longitude double precision;
alter table public.reports add column if not exists created_at timestamptz not null default now();
alter table public.reports add column if not exists expires_at timestamptz;
alter table public.reports add column if not exists still_valid_count integer not null default 0;
alter table public.reports add column if not exists no_longer_valid_count integer not null default 0;
create index if not exists reports_created_at_idx on public.reports (created_at desc);
create index if not exists reports_expires_at_idx on public.reports (expires_at);
create unique index if not exists reports_id_unique_idx on public.reports (id);

create table if not exists public.catches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  station_id text,
  species text not null,
  weight double precision,
  length double precision,
  notes text,
  latitude double precision,
  longitude double precision,
  image text,
  timestamp timestamptz not null default now()
);

alter table public.catches add column if not exists id uuid default gen_random_uuid();
alter table public.catches add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.catches add column if not exists station_id text;
alter table public.catches add column if not exists species text;
alter table public.catches add column if not exists weight double precision;
alter table public.catches add column if not exists length double precision;
alter table public.catches add column if not exists notes text;
alter table public.catches add column if not exists latitude double precision;
alter table public.catches add column if not exists longitude double precision;
alter table public.catches add column if not exists image text;
alter table public.catches add column if not exists timestamp timestamptz not null default now();
create index if not exists catches_timestamp_idx on public.catches (timestamp desc);
create index if not exists catches_station_idx on public.catches (station_id);
create unique index if not exists catches_id_unique_idx on public.catches (id);

-- Supporting tables already used by the existing Community service.
create table if not exists public.catch_likes (
  catch_id uuid not null references public.catches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (catch_id, user_id)
);

create table if not exists public.catch_comments (
  id uuid primary key default gen_random_uuid(),
  catch_id uuid not null references public.catches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.report_verifications (
  report_id uuid not null references public.reports(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_valid boolean not null,
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    avatar_url = excluded.avatar_url,
    updated_at = now();
  return new;
end;
$$;

insert into public.profiles (id, full_name, avatar_url)
select
  id,
  raw_user_meta_data ->> 'full_name',
  raw_user_meta_data ->> 'avatar_url'
from auth.users
on conflict (id) do update set
  full_name = excluded.full_name,
  avatar_url = excluded.avatar_url,
  updated_at = now();

drop trigger if exists create_profile_after_signup on auth.users;
create trigger create_profile_after_signup
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

drop trigger if exists sync_profile_after_auth_update on auth.users;
create trigger sync_profile_after_auth_update
after update of raw_user_meta_data on auth.users
for each row execute function public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.favorites enable row level security;
alter table public.reports enable row level security;
alter table public.catches enable row level security;
alter table public.catch_likes enable row level security;
alter table public.catch_comments enable row level security;
alter table public.report_verifications enable row level security;

-- Profiles: authenticated community members may read profiles; owners manage theirs.
drop policy if exists "profiles_authenticated_read" on public.profiles;
create policy "profiles_authenticated_read" on public.profiles
for select to authenticated using (true);
drop policy if exists "profiles_owner_insert" on public.profiles;
create policy "profiles_owner_insert" on public.profiles
for insert to authenticated with check (auth.uid() = id);
drop policy if exists "profiles_owner_update" on public.profiles;
create policy "profiles_owner_update" on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "profiles_owner_delete" on public.profiles;
create policy "profiles_owner_delete" on public.profiles
for delete to authenticated using (auth.uid() = id);

-- Favorites are private to their owner.
drop policy if exists "favorites_owner_read" on public.favorites;
create policy "favorites_owner_read" on public.favorites
for select to authenticated using (auth.uid() = user_id);
drop policy if exists "favorites_owner_insert" on public.favorites;
create policy "favorites_owner_insert" on public.favorites
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "favorites_owner_update" on public.favorites;
create policy "favorites_owner_update" on public.favorites
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "favorites_owner_delete" on public.favorites;
create policy "favorites_owner_delete" on public.favorites
for delete to authenticated using (auth.uid() = user_id);

-- Reports and catches are readable by authenticated community members.
drop policy if exists "reports_authenticated_read" on public.reports;
create policy "reports_authenticated_read" on public.reports
for select to authenticated using (true);
drop policy if exists "reports_owner_insert" on public.reports;
create policy "reports_owner_insert" on public.reports
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "reports_owner_update" on public.reports;
create policy "reports_owner_update" on public.reports
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "reports_owner_delete" on public.reports;
create policy "reports_owner_delete" on public.reports
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "catches_authenticated_read" on public.catches;
create policy "catches_authenticated_read" on public.catches
for select to authenticated using (true);
drop policy if exists "catches_owner_insert" on public.catches;
create policy "catches_owner_insert" on public.catches
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "catches_owner_update" on public.catches;
create policy "catches_owner_update" on public.catches
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "catches_owner_delete" on public.catches;
create policy "catches_owner_delete" on public.catches
for delete to authenticated using (auth.uid() = user_id);

-- Supporting community records are public to authenticated users and owner-written.
drop policy if exists "catch_likes_authenticated_read" on public.catch_likes;
create policy "catch_likes_authenticated_read" on public.catch_likes
for select to authenticated using (true);
drop policy if exists "catch_likes_owner_insert" on public.catch_likes;
create policy "catch_likes_owner_insert" on public.catch_likes
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "catch_likes_owner_delete" on public.catch_likes;
create policy "catch_likes_owner_delete" on public.catch_likes
for delete to authenticated using (auth.uid() = user_id);
drop policy if exists "catch_likes_owner_update" on public.catch_likes;
create policy "catch_likes_owner_update" on public.catch_likes
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "catch_comments_authenticated_read" on public.catch_comments;
create policy "catch_comments_authenticated_read" on public.catch_comments
for select to authenticated using (true);
drop policy if exists "catch_comments_owner_insert" on public.catch_comments;
create policy "catch_comments_owner_insert" on public.catch_comments
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "catch_comments_owner_update" on public.catch_comments;
create policy "catch_comments_owner_update" on public.catch_comments
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "catch_comments_owner_delete" on public.catch_comments;
create policy "catch_comments_owner_delete" on public.catch_comments
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "report_verifications_authenticated_read" on public.report_verifications;
create policy "report_verifications_authenticated_read" on public.report_verifications
for select to authenticated using (true);
drop policy if exists "report_verifications_owner_insert" on public.report_verifications;
create policy "report_verifications_owner_insert" on public.report_verifications
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "report_verifications_owner_update" on public.report_verifications;
create policy "report_verifications_owner_update" on public.report_verifications
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "report_verifications_owner_delete" on public.report_verifications;
create policy "report_verifications_owner_delete" on public.report_verifications
for delete to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.favorites to authenticated;
grant select, insert, update, delete on public.reports to authenticated;
grant select, insert, update, delete on public.catches to authenticated;
grant select, insert, update, delete on public.catch_likes to authenticated;
grant select, insert, update, delete on public.catch_comments to authenticated;
grant select, insert, update, delete on public.report_verifications to authenticated;
