create or replace function public.approve_payroll_period(p_period_id uuid) returns public.payroll_periods language plpgsql security definer set search_path=public as $$
declare pp public.payroll_periods; r record; a record; left_ded numeric; applied numeric;
begin
 if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح باعتماد المرتبات'; end if;
 select * into pp from public.payroll_periods where id=p_period_id for update;
 if pp.id is null then raise exception 'الفترة غير موجودة'; end if;
 if pp.status<>'draft' then raise exception 'الفترة اعتمدت أو ألغيت سابقًا'; end if;
 for r in select * from public.payroll_records where period_id=pp.id for update loop
   left_ded:=greatest(coalesce(r.advance_deduction,0),0);
   for a in select * from public.employee_advances where employee_id=r.employee_id and remaining_amount>0 order by advance_date,id for update loop
     exit when left_ded<=0;
     applied:=least(a.remaining_amount,left_ded);
     update public.employee_advances set remaining_amount=greatest(remaining_amount-applied,0),repayment_amount=coalesce(repayment_amount,0)+applied where id=a.id;
     left_ded:=left_ded-applied;
   end loop;
 end loop;
 update public.payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=pp.id returning * into pp;
 return pp;
end; $$;

create or replace function public.pay_payroll_record(p_record_id uuid,p_payment_method text,p_cash_register_id uuid default null,p_bank_id uuid default null) returns public.payroll_records language plpgsql security definer set search_path=public as $$
declare r public.payroll_records; pp public.payroll_periods; due numeric;
begin
 if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح بدفع المرتب'; end if;
 select * into r from public.payroll_records where id=p_record_id for update;
 if r.id is null then raise exception 'سجل المرتب غير موجود'; end if;
 select * into pp from public.payroll_periods where id=r.period_id;
 if pp.status<>'approved' then raise exception 'اعتمد فترة المرتبات أولًا'; end if;
 due:=greatest(coalesce(r.net_amount,0)-coalesce(r.paid_amount,0),0);
 if due<=0 then raise exception 'تم دفع هذا المرتب سابقًا'; end if;
 if p_payment_method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
 if p_payment_method='bank' and p_bank_id is null then raise exception 'اختر البنك'; end if;
 if p_payment_method='cash' then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_cash_register_id,'out','payroll',due,'payroll',r.id,auth.uid(),'دفع مرتب'); else insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_bank_id,'out','payroll',due,'payroll',r.id,auth.uid(),'دفع مرتب'); end if;
 update public.payroll_records set paid_amount=coalesce(paid_amount,0)+due,payment_status='paid',paid_at=now() where id=r.id returning * into r;
 return r;
end; $$;

grant execute on function public.approve_payroll_period(uuid) to authenticated;
grant execute on function public.pay_payroll_record(uuid,text,uuid,uuid) to authenticated;
