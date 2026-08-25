-- Bucket عام لقراءة الشعار من GitHub Pages، مع كتابة محصورة في المدير.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'factory-logos',
  'factory-logos',
  true,
  2097152,
  array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']::text[]
)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists factory_logo_manager_insert on storage.objects;
create policy factory_logo_manager_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'factory-logos'
  and name = 'factory-logo'
  and public.current_user_is_manager()
);

drop policy if exists factory_logo_manager_update on storage.objects;
create policy factory_logo_manager_update
on storage.objects for update to authenticated
using (
  bucket_id = 'factory-logos'
  and name = 'factory-logo'
  and public.current_user_is_manager()
)
with check (
  bucket_id = 'factory-logos'
  and name = 'factory-logo'
  and public.current_user_is_manager()
);

drop policy if exists factory_logo_manager_delete on storage.objects;
create policy factory_logo_manager_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'factory-logos'
  and name = 'factory-logo'
  and public.current_user_is_manager()
);
