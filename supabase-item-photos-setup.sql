-- =====================================================================
--  WheresMy — Item photo storage setup
--  Run this in the Supabase SQL Editor (after the auth/RLS setup).
--  Safe to re-run: every statement guards against already existing.
-- =====================================================================

-- 1. Column on items to hold the photo's storage path ("<household_id>/<uuid>.jpg")
alter table items add column if not exists image_path text;

-- 2. Private bucket for the photos (not publicly readable)
insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', false)
on conflict (id) do nothing;

-- 3. Access policies on the stored files: a logged-in user may only touch
--    photos inside their own household's folder. The folder is the first path
--    segment, e.g. "<household_id>/photo.jpg".
drop policy if exists "household read item photos"   on storage.objects;
drop policy if exists "household insert item photos" on storage.objects;
drop policy if exists "household update item photos" on storage.objects;
drop policy if exists "household delete item photos" on storage.objects;

create policy "household read item photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'item-photos'
           and (storage.foldername(name))[1] = public.auth_household_id()::text);

create policy "household insert item photos" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'item-photos'
                and (storage.foldername(name))[1] = public.auth_household_id()::text);

create policy "household update item photos" on storage.objects
    for update to authenticated
    using (bucket_id = 'item-photos'
           and (storage.foldername(name))[1] = public.auth_household_id()::text);

create policy "household delete item photos" on storage.objects
    for delete to authenticated
    using (bucket_id = 'item-photos'
           and (storage.foldername(name))[1] = public.auth_household_id()::text);
