-- AIFishMap catch location foundation.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

alter table public.catches
  add column if not exists place_name text,
  add column if not exists water_type text,
  add column if not exists location_privacy text not null default 'exact';

alter table public.catches
  drop constraint if exists catches_water_type_check,
  add constraint catches_water_type_check check (
    water_type is null or water_type in (
      'river', 'lake', 'reservoir', 'canal', 'danube', 'other'
    )
  ),
  drop constraint if exists catches_location_privacy_check,
  add constraint catches_location_privacy_check check (
    location_privacy in ('exact', 'approximate', 'hidden')
  );
