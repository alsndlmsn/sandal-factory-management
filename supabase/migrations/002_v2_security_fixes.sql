-- v2 security fixes and atomic sale approval
alter view public.v_stock_balances set (security_invoker = true);
alter view public.v_cash_balances set (security_invoker = true);

revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
grant execute on function public.current_user_has_permission(text) to authenticated;
grant execute on function public.current_user_is_manager() to authenticated;
grant execute on function public.stock_balance(uuid,uuid) to authenticated;
grant execute on function public.manager_dashboard_summary() to authenticated;
grant execute on function public.approve_sale(uuid) to authenticated;
grant execute on function public.approve_stock_movement(uuid) to authenticated;
grant execute on function public.approve_expense(uuid) to authenticated;
grant execute on function public.record_cash_transaction(text,uuid,public.movement_direction,text,numeric,text) to authenticated;
grant execute on function public.approve_production_order(uuid) to authenticated;

drop policy if exists attendance_corrections_read on public.attendance_corrections;
create policy attendance_corrections_read on public.attendance_corrections for select to authenticated using (public.current_user_has_permission('attendance.view'));
drop policy if exists attendance_corrections_create on public.attendance_corrections;
create policy attendance_corrections_create on public.attendance_corrections for insert to authenticated with check (public.current_user_has_permission('attendance.correct') and corrected_by=auth.uid());
drop policy if exists employee_history_read on public.employee_history;
create policy employee_history_read on public.employee_history for select to authenticated using (public.current_user_has_permission('employees.view'));
drop policy if exists employee_history_create on public.employee_history;
create policy employee_history_create on public.employee_history for insert to authenticated with check (public.current_user_has_permission('employees.edit') and changed_by=auth.uid());
drop policy if exists expense_categories_read on public.expense_categories;
create policy expense_categories_read on public.expense_categories for select to authenticated using (public.current_user_has_permission('expenses.view') or public.current_user_is_manager());
drop policy if exists expense_categories_manage on public.expense_categories;
create policy expense_categories_manage on public.expense_categories for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());

create or replace function public.approve_sale(p_sale_id uuid) returns public.sales language plpgsql security definer set search_path = public as $$
declare s public.sales; m public.stock_movements; item record; balance numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.approve') then raise exception 'غير مصرح باعتماد البيع'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if s.id is null or s.status <> 'draft' then raise exception 'الفاتورة غير قابلة للاعتماد'; end if;
  for item in select * from public.sale_items where sale_id=p_sale_id loop
    balance := public.stock_balance(item.product_id,s.warehouse_id);
    if balance < item.quantity then raise exception 'الرصيد غير كاف للصنف'; end if;
  end loop;
  update public.sales set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_sale_id returning * into s;
  insert into public.stock_movements(document_number,direction,movement_type,warehouse_id,related_sale_id,status,created_by,approved_by,approved_at)
    values ('SALE-'||s.invoice_number,'out','sale',s.warehouse_id,s.id,'approved',auth.uid(),auth.uid(),now()) returning * into m;
  insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_code,unit_cost)
    select m.id,product_id,quantity,unit_code,unit_cost from public.sale_items where sale_id=p_sale_id;
  if s.payment_method='cash' then insert into public.cash_transactions(transaction_number,cash_register_id,direction,transaction_type,amount,related_entity,related_id,created_by) values ('SALE-'||s.invoice_number,s.cash_register_id,'in','sale',s.total,'sales',s.id,auth.uid());
  else insert into public.bank_transactions(transaction_number,bank_id,direction,transaction_type,amount,related_entity,related_id,created_by) values (coalesce(s.bank_transaction_number,'SALE-'||s.invoice_number),s.bank_id,'in','sale',s.total,'sales',s.id,auth.uid()); end if;
  return s;
end; $$;
grant execute on function public.approve_sale(uuid) to authenticated;

create or replace function public.correct_attendance(p_attendance_id uuid,p_check_in_at timestamptz,p_check_out_at timestamptz,p_reason text) returns public.attendance_records language plpgsql security definer set search_path = public as $$
declare a public.attendance_records; updated public.attendance_records;
begin
  if auth.uid() is null or not public.current_user_has_permission('attendance.correct') then raise exception 'غير مصرح بتصحيح الحضور'; end if;
  select * into a from public.attendance_records where id=p_attendance_id for update;
  if a.id is null then raise exception 'سجل الحضور غير موجود'; end if;
  insert into public.attendance_corrections(attendance_id,old_check_in_at,old_check_out_at,new_check_in_at,new_check_out_at,reason,corrected_by) values(a.id,a.check_in_at,a.check_out_at,p_check_in_at,p_check_out_at,p_reason,auth.uid());
  update public.attendance_records set check_in_at=p_check_in_at,check_out_at=p_check_out_at,updated_at=now() where id=a.id returning * into updated; return updated;
end; $$;
grant execute on function public.correct_attendance(uuid,timestamptz,timestamptz,text) to authenticated;
create or replace function public.approve_payroll_period(p_period_id uuid) returns public.payroll_periods language plpgsql security definer set search_path = public as $$
declare p public.payroll_periods;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح باعتماد المرتبات'; end if;
  update public.payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_period_id and status='draft' returning * into p;
  if p.id is null then raise exception 'فترة المرتبات غير قابلة للاعتماد'; end if; return p;
end; $$;
grant execute on function public.approve_payroll_period(uuid) to authenticated;
