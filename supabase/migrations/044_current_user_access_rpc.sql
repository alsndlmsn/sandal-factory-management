create or replace function public.get_current_user_access()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
select jsonb_build_object(
  'profile', to_jsonb(p),
  'role_code', case when p.is_manager then 'manager' else r.code end,
  'role_name', case when p.is_manager then 'مدير' else coalesce(r.name_ar, r.code, 'غير محدد') end,
  'permissions', coalesce((
    select jsonb_agg(distinct perm.code)
    from public.user_roles ur2
    join public.role_permissions rp2 on rp2.role_id = ur2.role_id
    join public.permissions perm on perm.id = rp2.permission_id
    where ur2.user_id = p.id
  ), '[]'::jsonb)
)
from public.profiles p
left join public.user_roles ur on ur.user_id = p.id
left join public.roles r on r.id = ur.role_id
where p.id = auth.uid()
limit 1;
$$;

grant execute on function public.get_current_user_access() to authenticated;
revoke execute on function public.get_current_user_access() from anon;
