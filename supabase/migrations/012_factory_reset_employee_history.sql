create or replace function public.reset_factory_operational_data(p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare reset_at timestamptz := now();
begin
  if auth.uid() is null or not public.current_user_is_manager() then raise exception 'غير مصرح بإعادة ضبط بيانات المصنع'; end if;
  if p_confirmation <> 'إعادة ضبط المصنع' then raise exception 'عبارة التأكيد غير صحيحة'; end if;

  delete from public.payroll_records;
  delete from public.employee_incentives;
  delete from public.payroll_periods;
  delete from public.employee_advances;
  delete from public.attendance_corrections;
  delete from public.attendance_records;
  delete from public.production_outputs;
  delete from public.production_materials;
  delete from public.production_orders;
  delete from public.sale_items;
  delete from public.sales;
  delete from public.stock_movement_lines;
  delete from public.stock_movements;
  delete from public.expenses;
  delete from public.cash_transactions;
  delete from public.bank_transactions;
  delete from public.customers;
  delete from public.employee_history;
  delete from public.employees;
  delete from public.products;
  delete from public.warehouses;
  delete from public.cash_registers;
  delete from public.banks;
  delete from public.shifts;
  delete from public.departments;
  delete from public.job_titles;
  delete from public.product_categories;
  delete from public.expense_categories;

  insert into public.activity_logs(actor_id,action,entity_type,reason,severity,created_at)
  values(auth.uid(),'RESET_FACTORY','factory','إعادة ضبط بيانات التشغيل بطلب المدير','critical',reset_at);
  return jsonb_build_object('ok',true,'reset_at',reset_at);
end;
$$;
revoke execute on function public.reset_factory_operational_data(text) from public;
revoke execute on function public.reset_factory_operational_data(text) from anon;
grant execute on function public.reset_factory_operational_data(text) to authenticated;
