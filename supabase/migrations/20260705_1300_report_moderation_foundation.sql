-- AIFishMap report moderation foundation.
-- Apply manually after 20260705_1200_community_report_abuse.sql.
-- Reports are never deleted automatically.

alter table public.report_abuse
drop constraint if exists report_abuse_reason_check;

update public.report_abuse
set reason = case
  when reason = 'false_information' then 'fake_information'
  when reason in ('wrong_location', 'duplicate') then 'other'
  else reason
end
where reason in ('false_information', 'wrong_location', 'duplicate');

alter table public.report_abuse
add constraint report_abuse_reason_check check (
  reason in (
    'spam',
    'fake_information',
    'offensive_content',
    'dangerous_illegal_activity',
    'other'
  )
);

-- The underlying table retains report_id, user_id, reason, and created_at.
-- This service-role-only view provides aggregate counts for future moderation.
create or replace view public.report_moderation_summary
with (security_invoker = true)
as
select
  report_id,
  count(*)::integer as flagged_count,
  array_agg(reason order by created_at) as abuse_reasons,
  min(created_at) as first_flagged_at,
  max(created_at) as last_flagged_at
from public.report_abuse
group by report_id;

revoke all on public.report_moderation_summary from anon, authenticated;
grant select on public.report_moderation_summary to service_role;
