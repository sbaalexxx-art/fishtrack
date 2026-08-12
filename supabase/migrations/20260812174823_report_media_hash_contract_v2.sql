-- Applied to production Supabase on 2026-08-12.
alter table public.reports
  drop constraint if exists reports_image_hash_format_check;

alter table public.reports
  add constraint reports_image_hash_format_check
  check (
    image_hash is null
    or image_hash ~ '^[0-9a-f]{8}$'
    or image_hash ~ '^[0-9a-f]{64}$'
  );

comment on column public.reports.image_hash is
  'Legacy rows may contain 8-char FNV-1a hashes; new media-policy clients store SHA-256 (64 lowercase hex chars) of the exact privacy-sanitized JPEG bytes.';
