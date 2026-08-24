create or replace function public.grant_employee_incentive(p_batch_number text,p_title text,p_amount numeric,p_scope text,p_employee_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare inserted_count integer := 0;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح بإضافة الحوافز'; end if;
  if p_amount <= 0 or length(btrim(p_title)) < 2 then raise exception 'بيانات الحافز غير صحيحة'; end if;
  if p_scope='employee' then
    if p_employee_id is null then raise exception 'اختر الموظف المستحق للحافز'; end if;
    insert into public.employee_incentives(batch_number,employee_id,title,amount,created_by) values(p_batch_number,p_employee_id,p_title,p_amount,auth.uid());
    inserted_count := 1;
  elsif p_scope='all' then
    insert into public.employee_incentives(batch_number,employee_id,title,amount,created_by)
    select p_batch_number,id,p_title,p_amount,auth.uid() from public.employees where status='active';
    get diagnostics inserted_count = row_count;
  else
    raise exception 'نطاق الحافز غير معروف';
  end if;
  return inserted_count;
end;
$$;
revoke execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) from public;
revoke execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) from anon;
grant execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) to authenticated;
