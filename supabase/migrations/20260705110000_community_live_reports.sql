-- AIFishMap live community report support.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

alter table public.reports
  add column if not exists use_exact_location boolean not null default true,
  add column if not exists photo_url text;

do $$
begin
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
