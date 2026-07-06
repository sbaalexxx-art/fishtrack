-- AIFishMap Sprint 7.12: read-only reputation and trust foundation.
-- Apply after 20260706_0711_report_spam_detection.sql.

-- Replace the previous table-wide update grant with an explicit allow-list so
-- authenticated users cannot edit the legacy profiles.reputation value.
revoke update on public.profiles from authenticated;
grant update (username, full_name, avatar, avatar_url, country)
  on public.profiles to authenticated;

create or replace view public.user_reputation
with (security_barrier = true)
as
with report_activity as (
  select
    r.user_id,
    count(*)::integer as reports_count,
    count(*) filter (where r.is_suspicious)::integer
      as suspicious_reports_count,
    coalesce(sum(v.confirmed_count), 0)::integer as confirmed_count,
    coalesce(sum(v.not_accurate_count), 0)::integer as not_accurate_count,
    coalesce(sum(a.abuse_flags_count), 0)::integer as abuse_flags_count,
    max(greatest(
      r.created_at,
      coalesce(v.updated_at, r.created_at),
      coalesce(a.updated_at, r.created_at)
    )) as updated_at
  from public.reports r
  left join (
    select
      report_id,
      count(*) filter (where is_valid)::integer as confirmed_count,
      count(*) filter (where not is_valid)::integer as not_accurate_count,
      max(created_at) as updated_at
    from public.report_verifications
    group by report_id
  ) v on v.report_id = r.id
  left join (
    select
      report_id,
      count(*)::integer as abuse_flags_count,
      max(created_at) as updated_at
    from public.report_abuse
    group by report_id
  ) a on a.report_id = r.id
  group by r.user_id
),
catch_activity as (
  select
    user_id,
    count(*)::integer as catches_count,
    max(timestamp) as updated_at
  from public.catches
  where user_id is not null
  group by user_id
),
metrics as (
  select
    p.id as user_id,
    coalesce(r.reports_count, 0)::integer as reports_count,
    coalesce(c.catches_count, 0)::integer as catches_count,
    coalesce(r.confirmed_count, 0)::integer as confirmed_count,
    coalesce(r.not_accurate_count, 0)::integer as not_accurate_count,
    coalesce(r.abuse_flags_count, 0)::integer as abuse_flags_count,
    coalesce(r.suspicious_reports_count, 0)::integer
      as suspicious_reports_count,
    greatest(
      p.updated_at,
      coalesce(r.updated_at, p.updated_at),
      coalesce(c.updated_at, p.updated_at)
    ) as updated_at
  from public.profiles p
  left join report_activity r on r.user_id = p.id
  left join catch_activity c on c.user_id = p.id
),
scored as (
  select
    metrics.*,
    greatest(0, least(100,
      50
      + confirmed_count * 2
      - not_accurate_count * 3
      - abuse_flags_count * 5
      - suspicious_reports_count * 4
      + catches_count
      + reports_count
    ))::integer as reputation_score
  from metrics
)
select
  user_id,
  reputation_score,
  case
    when reputation_score >= 85 then 'Expert'
    when reputation_score >= 65 then 'Reliable'
    when reputation_score >= 40 then 'Trusted'
    else 'New'
  end::text as trust_level,
  reports_count,
  catches_count,
  confirmed_count,
  not_accurate_count,
  abuse_flags_count,
  suspicious_reports_count,
  updated_at
from scored;

revoke all on public.user_reputation from public;
revoke all on public.user_reputation from anon;
revoke all on public.user_reputation from authenticated;
grant select on public.user_reputation to authenticated;
grant select on public.user_reputation to service_role;

comment on view public.user_reputation is
  'Read-only reputation calculated from community activity; users cannot edit it.';
