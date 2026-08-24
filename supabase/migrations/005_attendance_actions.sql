create or replace function public.toggle_employee_attendance(p_employee_id uuid, p_action text)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.attendance_records;
  open_record public.attendance_records;
begin
  if auth.uid() is null or not public.current_user_has_permission('attendance.create') then
    raise exception 'غير مصرح بتسجيل الحضور';
  end if;
  if not exists (select 1 from public.employees where id=p_employee_id and status='active') then
    raise exception 'الموظف غير موجود أو غير نشط';
  end if;
  if p_action = 'check_in' then
    select * into open_record from public.attendance_records
    where employee_id=p_employee_id and check_out_at is null
    order by check_in_at desc limit 1;
    if open_record.id is not null then return open_record; end if;
    insert into public.attendance_records(employee_id,status,check_in_at,recorded_by)
    values(p_employee_id,'present',now(),auth.uid()) returning * into result;
    return result;
  elsif p_action = 'check_out' then
    update public.attendance_records
    set check_out_at=now(), updated_at=now()
    where id=(select id from public.attendance_records where employee_id=p_employee_id and check_out_at is null order by check_in_at desc limit 1)
    returning * into result;
    if result.id is null then raise exception 'لا يوجد حضور مفتوح لهذا الموظف'; end if;
    return result;
  else
    raise exception 'الإجراء غير معروف';
  end if;
end;
$$;
revoke execute on function public.toggle_employee_attendance(uuid,text) from public;
revoke execute on function public.toggle_employee_attendance(uuid,text) from anon;
grant execute on function public.toggle_employee_attendance(uuid,text) to authenticated;
