-- AIFishMap community report abuse foundation.
-- Apply manually in the Supabase SQL Editor. Reports are never deleted automatically.

create table if not exists public.report_abuse (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (
    reason in (
      'false_information',
      'wrong_location',
      'spam',
      'offensive_content',
      'duplicate',
      'other'
    )
  ),
  created_at timestamptz not null default now(),
  unique (report_id, user_id)
);

alter table public.report_abuse enable row level security;

drop policy if exists "report_abuse_owner_read" on public.report_abuse;
create policy "report_abuse_owner_read" on public.report_abuse
for select to authenticated using (auth.uid() = user_id);

drop policy if exists "report_abuse_owner_insert" on public.report_abuse;
create policy "report_abuse_owner_insert" on public.report_abuse
for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "report_abuse_owner_update" on public.report_abuse;
create policy "report_abuse_owner_update" on public.report_abuse
for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update on public.report_abuse to authenticated;
