-- Applied to production Supabase on 2026-08-12.
alter table public.catches
  add column if not exists image_sha256 text;

alter table public.catches
  drop constraint if exists catches_image_sha256_format_check;

alter table public.catches
  add constraint catches_image_sha256_format_check
  check (image_sha256 is null or image_sha256 ~ '^[0-9a-f]{64}$');

create unique index if not exists catches_user_image_sha256_unique
  on public.catches(user_id, image_sha256)
  where image_sha256 is not null;

comment on column public.catches.image_sha256 is
  'SHA-256 of the exact privacy-sanitized JPEG bytes uploaded to catch-images; used for owner-scoped duplicate protection and media audit.';
