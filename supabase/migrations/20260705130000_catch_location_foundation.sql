-- AIFishMap catch location foundation.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

alter table public.catches
  add column if not exists place_name text,
  add column if not exists water_type text,
  add column if not exists location_privacy text not null default 'exact';

do $$
declare
  incompatible_column text;
begin
  select required.column_name
    into incompatible_column
  from (
    values
      ('place_name', 'text', 'YES'),
      ('water_type', 'text', 'YES'),
      ('location_privacy', 'text', 'NO')
  ) as required(column_name, data_type, is_nullable)
  left join information_schema.columns as actual
    on actual.table_schema = 'public'
    and actual.table_name = 'catches'
    and actual.column_name = required.column_name
  where actual.column_name is null
    or actual.data_type <> required.data_type
    or actual.is_nullable <> required.is_nullable
  limit 1;

  if incompatible_column is not null then
    raise exception
      'catches has an incompatible location column contract at %',
      incompatible_column;
  end if;

  if not exists (
    select 1
    from pg_attrdef as default_value
    join pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
      and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.catches'::regclass
      and attribute.attname = 'location_privacy'
      and pg_get_expr(default_value.adbin, default_value.adrelid) = '''exact''::text'
  ) then
    raise exception
      'catches.location_privacy must have default exact';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.catches'::regclass
      and conname = 'catches_water_type_check'
  ) then
    alter table public.catches
      add constraint catches_water_type_check check (
        water_type is null or water_type in (
          'river', 'lake', 'reservoir', 'canal', 'danube', 'other'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.catches'::regclass
      and conname = 'catches_location_privacy_check'
  ) then
    alter table public.catches
      add constraint catches_location_privacy_check check (
        location_privacy in ('exact', 'approximate', 'hidden')
      );
  end if;
end;
$$;
