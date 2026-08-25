-- مسار حذف المستخدم من التشغيل: أرشفة وتعطيل الحساب مع حفظ التاريخ وعدم كسر القيود المرجعية.
create or replace function public.admin_delete_user(
  p_user_id uuid,
  p_reason text default null
) returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  target_profile public.profiles;
  result_profile public.profiles;
  reason_text text := coalesce(nullif(trim(p_reason), ''), 'حذف مستخدم من التشغيل');
  archived_at timestamptz := now();
begin
  if auth.uid() is null or not public.current_user_is_manager() then
    raise exception 'غير مصرح بحذف المستخدمين';
  end if;
  if p_user_id is null then
    raise exception 'معرّف المستخدم مطلوب';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'لا يمكن للمدير حذف حسابه الحالي';
  end if;

  select * into target_profile
  from public.profiles
  where id = p_user_id and deleted_at is null
  for update;

  if target_profile.id is null then
    raise exception 'المستخدم غير موجود أو مؤرشف بالفعل';
  end if;

  update public.profiles
  set is_enabled = false,
      deleted_at = archived_at,
      deleted_by = auth.uid()
  where id = p_user_id
  returning * into result_profile;

  delete from public.user_roles where user_id = p_user_id;

  insert into public.activity_logs(
    actor_id, action, entity_type, entity_id,
    old_data, new_data, reason, severity
  ) values (
    auth.uid(), 'user_delete', 'profile', p_user_id,
    to_jsonb(target_profile),
    jsonb_build_object('is_enabled', false, 'deleted_at', archived_at),
    reason_text, 'critical'
  );

  return result_profile;
end;
$$;

grant execute on function public.admin_delete_user(uuid, text) to authenticated;
revoke execute on function public.admin_delete_user(uuid, text) from anon, public;
