-- ربط اعتماد فاتورة الشراء بسجل supplier_payments بالإضافة إلى حركة الخزنة أو البنك.
create or replace function public.approve_purchase(p_purchase_id uuid)
returns public.purchases
language plpgsql security definer set search_path=public as $$
declare pur public.purchases; item record; mov public.stock_movements;
begin
  if auth.uid() is null or not public.current_user_has_permission('purchases.approve') then raise exception 'غير مصرح باعتماد الشراء'; end if;
  select * into pur from public.purchases where id=p_purchase_id for update;
  if pur.id is null then raise exception 'فاتورة الشراء غير موجودة'; end if;
  if pur.status<>'draft' then raise exception 'فاتورة الشراء اعتمدت أو ألغيت سابقًا'; end if;
  insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at)
  values('in','purchase',pur.id,pur.warehouse_id,'approved',auth.uid(),auth.uid(),now()) returning * into mov;
  for item in select * from public.purchase_items where purchase_id=pur.id loop
    insert into public.stock_movement_lines(movement_id,product_id,raw_material_id,quantity,unit_name,cost_price,notes)
    values(mov.id,item.product_id,item.raw_material_id,item.quantity,item.unit_name,item.unit_price,'شراء '||pur.purchase_number);
  end loop;
  if pur.paid_amount>0 and pur.payment_method='cash' then
    insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes)
    values(pur.cash_register_id,'out','purchase',pur.paid_amount,'purchase',pur.id,auth.uid(),'سداد شراء '||pur.purchase_number);
  end if;
  if pur.paid_amount>0 and pur.payment_method='bank' then
    insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes)
    values(pur.bank_id,'out','purchase',pur.paid_amount,'purchase',pur.id,auth.uid(),'سداد شراء '||pur.purchase_number);
  end if;
  if pur.paid_amount>0 then
    insert into public.supplier_payments(supplier_id,purchase_id,amount,payment_method,cash_register_id,bank_id,created_by)
    values(pur.supplier_id,pur.id,pur.paid_amount,pur.payment_method,pur.cash_register_id,pur.bank_id,auth.uid());
  end if;
  update public.purchases set status='approved',approved_by=auth.uid(),approved_at=now() where id=pur.id returning * into pur;
  return pur;
end; $$;

grant execute on function public.approve_purchase(uuid) to authenticated;
revoke execute on function public.approve_purchase(uuid) from anon;
