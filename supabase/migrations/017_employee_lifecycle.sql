insert into public.permissions(code,name_ar,module) values('employees.edit','تعديل ملف عامل','employees'),('employees.suspend','تعليق عامل','employees') on conflict(code) do nothing;
create or replace function public.update_employee_profile(p_employee_id uuid,p_name text,p_phone text default null,p_base_salary numeric default 0,p_notes text default null) returns public.employees language plpgsql security definer set search_path=public as $$
declare e public.employees;
begin
 if auth.uid() is null or not public.current_user_has_permission('employees.edit') then raise exception 'غير مصرح بتعديل ملف العامل'; end if;
 if p_employee_id is null or nullif(btrim(p_name),'') is null then raise exception 'بيانات العامل غير مكتملة'; end if;
 update public.employees set full_name=btrim(p_name),phone=p_phone,base_salary=greatest(coalesce(p_base_salary,0),0),notes=p_notes,updated_at=now() where id=p_employee_id returning * into e;
 if e.id is null then raise exception 'العامل غير موجود'; end if;
 return e;
end; $$;
create or replace function public.set_employee_status(p_employee_id uuid,p_status text) returns public.employees language plpgsql security definer set search_path=public as $$
declare e public.employees;
begin
 if auth.uid() is null or not public.current_user_has_permission('employees.suspend') then raise exception 'غير مصرح بتغيير حالة العامل'; end if;
 if p_status not in('active','suspended','leave','archived') then raise exception 'حالة العامل غير صحيحة'; end if;
 update public.employees set status=p_status,updated_at=now() where id=p_employee_id returning * into e;
 if e.id is null then raise exception 'العامل غير موجود'; end if;
 return e;
end; $$;
grant execute on function public.update_employee_profile(uuid,text,text,numeric,text) to authenticated;
grant execute on function public.set_employee_status(uuid,text) to authenticated;
