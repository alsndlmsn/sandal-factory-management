-- ضوابط إدارة المستخدمين: الحساب المعلّق يفقد الصلاحيات، والمدير يحدّث الاسم والدور والحالة عبر RPC آمنة.
create or replace function public.current_user_has_permission(p_code text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1
    from public.profiles me
    where me.id=auth.uid() and me.is_enabled=true
      and (
        me.is_manager=true
        or exists(
          select 1 from public.user_roles ur
          join public.role_permissions rp on rp.role_id=ur.role_id
          join public.permissions p on p.id=rp.permission_id
          where ur.user_id=me.id and p.code=p_code
        )
      )
  )
$$;

create or replace function public.admin_update_user(
  p_user_id uuid,p_full_name text default null,p_role_code text default null,p_is_enabled boolean default null
) returns public.profiles
language plpgsql security definer set search_path=public as $$
declare result public.profiles; selected_role uuid;
begin
  if auth.uid() is null or not public.current_user_is_manager() then raise exception 'غير مصرح بإدارة المستخدمين'; end if;
  if p_user_id is null then raise exception 'معرّف المستخدم مطلوب'; end if;
  if p_user_id=auth.uid() and p_is_enabled=false then raise exception 'لا يمكن للمدير تعليق حسابه الحالي'; end if;
  if p_role_code is not null then
    select id into selected_role from public.roles where code=p_role_code limit 1;
    if selected_role is null then raise exception 'الدور المحدد غير موجود'; end if;
    update public.user_roles set role_id=selected_role where user_id=p_user_id;
    if not found then insert into public.user_roles(user_id,role_id) values(p_user_id,selected_role); end if;
  end if;
  update public.profiles set full_name=coalesce(nullif(trim(p_full_name),''),full_name),is_enabled=coalesce(p_is_enabled,is_enabled) where id=p_user_id returning * into result;
  if result.id is null then raise exception 'المستخدم غير موجود'; end if;
  return result;
end; $$;

grant execute on function public.admin_update_user(uuid,text,text,boolean) to authenticated;
revoke execute on function public.admin_update_user(uuid,text,text,boolean) from anon;
