-- AIFishMap live community report support.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

alter table public.reports
  add column if not exists use_exact_location boolean not null default true,
  add column if not exists photo_url text;

do $$
declare
  incompatible_column text;
begin
  select required.column_name
    into incompatible_column
  from (
    values
      ('use_exact_location', 'boolean', 'NO'),
      ('photo_url', 'text', 'YES')
  ) as required(column_name, data_type, is_nullable)
  left join information_schema.columns as actual
    on actual.table_schema = 'public'
    and actual.table_name = 'reports'
    and actual.column_name = required.column_name
  where actual.column_name is null
    or actual.data_type <> required.data_type
    or actual.is_nullable <> required.is_nullable
  limit 1;

  if incompatible_column is not null then
    raise exception
      'reports has an incompatible live-report column contract at %',
      incompatible_column;
  end if;

  if not exists (
    select 1
    from pg_attrdef as default_value
    join pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
      and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.reports'::regclass
      and attribute.attname = 'use_exact_location'
      and pg_get_expr(default_value.adbin, default_value.adrelid) = 'true'
  ) then
    raise exception
      'reports.use_exact_location must have default true';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'reports'
  ) then
    alter publication supabase_realtime add table public.reports;
  end if;
end
$$;
