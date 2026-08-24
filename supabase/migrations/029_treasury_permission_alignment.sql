-- مواءمة صلاحية العرض في الخزائن والبنوك مع سياسات RLS الحالية.
insert into public.permissions(code,name_ar,module) values('treasury.view','عرض الخزائن والبنوك','finance') on conflict(code) do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='finance' and p.code='treasury.view'
on conflict(role_id,permission_id) do nothing;
