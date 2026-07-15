-- AIFishMap storage buckets and object policies.
-- Apply manually in the Supabase SQL Editor. This file is not executed by the app.

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('catch-images', 'catch-images', true),
  ('report-photos', 'report-photos', true)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public;

-- Public URLs are used by the app. Authenticated users may list/read objects,
-- while mutations are restricted to the user's own user_id/filename folder.

drop policy if exists "Authenticated users can read avatars" on storage.objects;
create policy "Authenticated users can read avatars"
on storage.objects for select
to authenticated
using (bucket_id = 'avatars');

drop policy if exists "Users can upload own avatars" on storage.objects;
create policy "Users can upload own avatars"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can update own avatars" on storage.objects;
create policy "Users can update own avatars"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can delete own avatars" on storage.objects;
create policy "Users can delete own avatars"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Authenticated users can read catch images" on storage.objects;
create policy "Authenticated users can read catch images"
on storage.objects for select
to authenticated
using (bucket_id = 'catch-images');

drop policy if exists "Users can upload own catch images" on storage.objects;
create policy "Users can upload own catch images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'catch-images'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can update own catch images" on storage.objects;
create policy "Users can update own catch images"
on storage.objects for update
to authenticated
using (
  bucket_id = 'catch-images'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'catch-images'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can delete own catch images" on storage.objects;
create policy "Users can delete own catch images"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'catch-images'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Authenticated users can read report photos" on storage.objects;
create policy "Authenticated users can read report photos"
on storage.objects for select
to authenticated
using (bucket_id = 'report-photos');

drop policy if exists "Users can upload own report photos" on storage.objects;
create policy "Users can upload own report photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'report-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can update own report photos" on storage.objects;
create policy "Users can update own report photos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'report-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'report-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can delete own report photos" on storage.objects;
create policy "Users can delete own report photos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'report-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);
