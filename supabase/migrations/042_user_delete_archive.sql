-- حذف المستخدم من التشغيل مع حفظ التاريخ المحاسبي والتدقيقي.
alter table public.profiles
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid;

create index if not exists profiles_deleted_at_idx on public.profiles(deleted_at);

comment on column public.profiles.deleted_at is 'وقت إيقاف وأرشفة المستخدم؛ لا يُحذف التاريخ المرتبط به.';
comment on column public.profiles.deleted_by is 'معرّف المدير الذي نفّذ الأرشفة.';
