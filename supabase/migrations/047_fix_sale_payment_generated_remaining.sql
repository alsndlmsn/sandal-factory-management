-- remaining_amount عمود مولّد؛ لا يجوز تحديثه مباشرة عند تسجيل دفعة لاحقة.
create or replace function public.add_sale_payment(
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_cash_register_id uuid default null,
  p_bank_id uuid default null,
  p_reference text default null
) returns public.sales
language plpgsql security definer set search_path=public as $$
declare
  s public.sales;
  due numeric;
  method text;
  final_method text;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.create') then
    raise exception 'غير مصرح بإضافة دفعة';
  end if;
  select * into s from public.sales where id=p_sale_id for update;
  if s.id is null or s.status<>'approved' then
    raise exception 'الفاتورة غير موجودة أو غير معتمدة';
  end if;
  due:=greatest(coalesce(s.total,0)-coalesce(s.paid_amount,0),0);
  if p_amount<=0 or p_amount>due then
    raise exception 'قيمة الدفعة أكبر من المتبقي أو غير صحيحة';
  end if;
  method:=coalesce(nullif(p_payment_method,''),'cash');
  if method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
  if method='bank' and p_bank_id is null then raise exception 'اختر البنك'; end if;
  insert into public.sale_payments(sale_id,amount,payment_method,cash_register_id,bank_id,reference,created_by)
  values(s.id,p_amount,method,p_cash_register_id,p_bank_id,p_reference,auth.uid());
  if method='cash' then
    insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,reference,created_by,notes)
    values(p_cash_register_id,'in','sale_payment',p_amount,'sale',s.id,p_reference,auth.uid(),'دفعة لاحقة لفاتورة');
  else
    insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,reference,created_by,notes)
    values(p_bank_id,'in','sale_payment',p_amount,'sale',s.id,p_reference,auth.uid(),'دفعة لاحقة لفاتورة');
  end if;
  final_method:=case when method='cash' then 'cash' else 'bank' end;
  -- remaining_amount is generated from total and paid_amount.
  update public.sales
    set paid_amount=coalesce(paid_amount,0)+p_amount,
        payment_method=case
          when greatest(total-(coalesce(paid_amount,0)+p_amount),0)=0 then final_method
          else 'partial'
        end
    where id=s.id returning * into s;
  return s;
end; $$;

grant execute on function public.add_sale_payment(uuid,numeric,text,uuid,uuid,text) to authenticated;
revoke execute on function public.add_sale_payment(uuid,numeric,text,uuid,uuid,text) from anon;
