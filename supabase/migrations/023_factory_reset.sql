-- إعادة ضبط بيانات التشغيل مع الحفاظ على حسابات المستخدمين والأدوار والصلاحيات وإعدادات المصنع.
create or replace function public.reset_factory_data(p_confirmation text)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.current_user_is_manager() then
    raise exception 'غير مصرح بإعادة ضبط بيانات المصنع';
  end if;
  if btrim(coalesce(p_confirmation,'')) <> 'إعادة ضبط المصنع' then
    raise exception 'عبارة التأكيد غير صحيحة';
  end if;

  truncate table
    public.activity_logs,
    public.return_refunds,
    public.return_items,
    public.returns,
    public.sale_payments,
    public.sale_items,
    public.sales,
    public.supplier_payments,
    public.purchase_items,
    public.purchases,
    public.raw_materials,
    public.suppliers,
    public.production_outputs,
    public.production_materials,
    public.production_orders,
    public.stock_movement_lines,
    public.stock_movements,
    public.damaged_goods,
    public.cash_transactions,
    public.bank_transactions,
    public.finance_transfers,
    public.cash_counts,
    public.expenses,
    public.expense_categories,
    public.payroll_records,
    public.payroll_periods,
    public.employee_incentives,
    public.employee_advances,
    public.attendance_corrections,
    public.attendance_records,
    public.employee_history,
    public.employees,
    public.departments,
    public.job_titles,
    public.shifts,
    public.customers,
    public.warehouses,
    public.products,
    public.product_categories,
    public.units,
    public.cash_registers,
    public.banks
  restart identity;

  alter sequence if exists public.product_seq restart with 1;
  alter sequence if exists public.employee_seq restart with 1;
  alter sequence if exists public.warehouse_seq restart with 1;
  alter sequence if exists public.movement_seq restart with 1;
  alter sequence if exists public.supplier_seq restart with 1;
  alter sequence if exists public.raw_seq restart with 1;
  alter sequence if exists public.purchase_seq restart with 1;
  alter sequence if exists public.invoice_seq restart with 1;
  alter sequence if exists public.return_seq restart with 1;
  alter sequence if exists public.damage_seq restart with 1;
  alter sequence if exists public.cash_seq restart with 1;
  alter sequence if exists public.bank_seq restart with 1;
  alter sequence if exists public.cash_tx_seq restart with 1;
  alter sequence if exists public.bank_tx_seq restart with 1;
  alter sequence if exists public.expense_seq restart with 1;

  insert into public.activity_logs(actor_id, action, entity_type, reason, severity)
  values (auth.uid(), 'RESET', 'factory', 'إعادة ضبط بيانات التشغيل مع الحفاظ على المستخدمين والصلاحيات', 'critical');
end;
$$;

revoke all on function public.reset_factory_data(text) from public;
grant execute on function public.reset_factory_data(text) to authenticated;
