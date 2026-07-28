-- Keep the denormalized report counters synchronized with authoritative votes.
create or replace function public.sync_report_verification_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_report_id uuid;
  previous_report_id uuid;
  affected_report_id uuid;
begin
  if tg_op = 'INSERT' then
    target_report_id := new.report_id;
  elsif tg_op = 'UPDATE' then
    target_report_id := new.report_id;
    if old.report_id is distinct from new.report_id then
      previous_report_id := old.report_id;
    end if;
  else
    target_report_id := old.report_id;
  end if;

  for affected_report_id in
    select distinct report_id
    from unnest(array[target_report_id, previous_report_id]) as affected(
      report_id
    )
    where report_id is not null
    order by report_id
  loop
    -- Serialize recalculation per report so concurrent votes cannot lose counts.
    perform 1
    from public.reports
    where id = affected_report_id
    for update;

    update public.reports as report
    set
      still_valid_count = (
        select count(*)::integer
        from public.report_verifications as verification
        where verification.report_id = affected_report_id
          and verification.is_valid is true
      ),
      no_longer_valid_count = (
        select count(*)::integer
        from public.report_verifications as verification
        where verification.report_id = affected_report_id
          and verification.is_valid is false
      )
    where report.id = affected_report_id;
  end loop;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function public.sync_report_verification_counts() is
  'Recalculates report verification counters after authoritative vote changes.';

-- Clients must not invoke the trigger function directly through RPC.
revoke all privileges
  on function public.sync_report_verification_counts()
  from public, anon, authenticated;

-- Accept verification votes without trusting client identity or timestamps.
create or replace function public.submit_report_verification(
  p_report_id uuid,
  p_is_valid boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
begin
  if caller_user_id is null then
    raise exception 'Authentication is required.'
      using errcode = '42501';
  end if;
  if p_report_id is null then
    raise exception 'Report ID must not be null.'
      using errcode = '22004';
  end if;
  if p_is_valid is null then
    raise exception 'Verification value must not be null.'
      using errcode = '22004';
  end if;

  insert into public.report_verifications (
    report_id,
    user_id,
    is_valid,
    created_at
  )
  values (
    p_report_id,
    caller_user_id,
    p_is_valid,
    now()
  )
  on conflict (report_id, user_id)
  do update set
    is_valid = excluded.is_valid,
    created_at = now();
end;
$$;

comment on function public.submit_report_verification(uuid, boolean) is
  'Submits or replaces the authenticated user verification for a report.';

revoke all privileges
  on function public.submit_report_verification(uuid, boolean)
  from public, anon, authenticated;

grant execute
  on function public.submit_report_verification(uuid, boolean)
  to authenticated;

-- Mobile clients may read and create reports, but never mutate saved rows.
revoke all privileges
  on table public.reports
  from public, anon, authenticated;

grant select on table public.reports to authenticated;

grant insert (
  user_id,
  type,
  category,
  description,
  image_url,
  latitude,
  longitude,
  created_at,
  expires_at,
  spam_score,
  is_suspicious,
  spam_reason,
  image_hash
) on table public.reports to authenticated;

-- Verification rows are private implementation details behind the RPC.
revoke all privileges
  on table public.report_verifications
  from public, anon, authenticated;

drop trigger if exists report_verifications_sync_counts
  on public.report_verifications;

create trigger report_verifications_sync_counts
after insert or update or delete on public.report_verifications
for each row
execute function public.sync_report_verification_counts();

-- Backfill every report, including reports that currently have zero votes.
update public.reports as report
set
  still_valid_count = (
    select count(*)::integer
    from public.report_verifications as verification
    where verification.report_id = report.id
      and verification.is_valid is true
  ),
  no_longer_valid_count = (
    select count(*)::integer
    from public.report_verifications as verification
    where verification.report_id = report.id
      and verification.is_valid is false
  );
