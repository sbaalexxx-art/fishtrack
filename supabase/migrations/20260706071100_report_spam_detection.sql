-- AIFishMap Sprint 7.11: rule-based report spam detection storage.
-- Apply after 20260705_1300_report_moderation_foundation.sql.
-- Reports are scored for moderator review; this migration does not hide,
-- delete, or reject reports and does not block users.

alter table public.reports
  add column if not exists spam_score integer not null default 0,
  add column if not exists is_suspicious boolean not null default false,
  add column if not exists spam_reason text,
  add column if not exists image_hash text;

alter table public.reports
  drop constraint if exists reports_spam_score_check;

alter table public.reports
  add constraint reports_spam_score_check
  check (spam_score between 0 and 100);

comment on column public.reports.spam_score is
  'Rule-based spam score: 0-30 normal, 31-60 suspicious, 61-100 likely spam.';

comment on column public.reports.is_suspicious is
  'Marks a report for moderator review without hiding or deleting it.';

comment on column public.reports.spam_reason is
  'Human-readable reasons that contributed to the spam score.';

comment on column public.reports.image_hash is
  'Optional image hash used to detect duplicate report images.';

create index if not exists reports_user_created_at_idx
  on public.reports (user_id, created_at desc);

create index if not exists reports_suspicious_created_at_idx
  on public.reports (created_at desc)
  where is_suspicious = true;

create index if not exists reports_user_image_hash_idx
  on public.reports (user_id, image_hash)
  where image_hash is not null;

create or replace view public.suspicious_report_moderation
with (security_invoker = true)
as
select
  id as report_id,
  user_id,
  type,
  category,
  description,
  image_url,
  latitude,
  longitude,
  spam_score,
  spam_reason,
  image_hash,
  created_at,
  expires_at
from public.reports
where is_suspicious = true;

revoke all on public.suspicious_report_moderation from public;
revoke all on public.suspicious_report_moderation from anon;
revoke all on public.suspicious_report_moderation from authenticated;
grant select on public.suspicious_report_moderation to service_role;
