-- Applied to production Supabase on 2026-08-12.
-- Hard server-side guard: client compression is not trusted as the only limit.
update storage.buckets
set file_size_limit = case id
      when 'catch-images' then 2097152
      when 'report-photos' then 1572864
      when 'avatars' then 1048576
      else file_size_limit
    end,
    allowed_mime_types = case id
      when 'catch-images' then array['image/jpeg','image/png','image/webp','image/heic','image/heif']::text[]
      when 'report-photos' then array['image/jpeg','image/png','image/webp','image/heic','image/heif']::text[]
      when 'avatars' then array['image/jpeg','image/png','image/webp','image/heic','image/heif']::text[]
      else allowed_mime_types
    end,
    updated_at = now()
where id in ('catch-images','report-photos','avatars');
