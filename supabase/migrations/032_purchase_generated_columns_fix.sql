-- إصلاح دالة الشراء: remaining_amount وpurchase_items.total أعمدة مولّدة ولا تقبل INSERT مباشر.
create or replace function public.create_purchase_draft_v2(
  p_supplier_id uuid,p_warehouse_id uuid,p_items jsonb,p_payment_method text default 'credit',p_paid_amount numeric default 0,
  p_cash_register_id uuid default null,p_bank_id uuid default null,p_discount numeric default 0,p_supplier_invoice text default null,p_notes text default null
) returns public.purchases
language plpgsql security definer set search_path=public as $$
declare pur public.purchases; item jsonb; item_total numeric:=0; qty numeric; price numeric; item_name text; raw_id uuid; prod_id uuid; paid numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('purchases.create') then raise exception 'غير مصرح بإنشاء شراء'; end if;
  if p_supplier_id is null or p_warehouse_id is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'اختر المورد والمخزن وأضف بندًا واحدًا على الأقل'; end if;
  if p_payment_method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
  if p_payment_method='bank' and p_bank_id is null then raise exception 'اختر البنك'; end if;
  for item in select value from jsonb_array_elements(p_items) loop
    qty:=coalesce((item->>'quantity')::numeric,0); price:=coalesce((item->>'unit_price')::numeric,0); item_name:=nullif(btrim(item->>'item_name'),'');
    if qty<=0 or price<0 or item_name is null then raise exception 'بيانات بند الشراء غير صحيحة'; end if;
    raw_id:=nullif(item->>'raw_material_id','')::uuid; prod_id:=nullif(item->>'product_id','')::uuid;
    if raw_id is null and prod_id is null then raise exception 'اربط كل بند بخامة أو منتج'; end if;
    item_total:=item_total+(qty*price);
  end loop;
  item_total:=greatest(item_total-greatest(coalesce(p_discount,0),0),0);
  paid:=least(greatest(coalesce(p_paid_amount,0),0),item_total);
  insert into public.purchases(supplier_id,warehouse_id,total,discount,paid_amount,payment_method,cash_register_id,bank_id,supplier_invoice,notes,created_by)
  values(p_supplier_id,p_warehouse_id,item_total,greatest(coalesce(p_discount,0),0),paid,coalesce(nullif(p_payment_method,''),'credit'),p_cash_register_id,p_bank_id,p_supplier_invoice,p_notes,auth.uid()) returning * into pur;
  for item in select value from jsonb_array_elements(p_items) loop
    qty:=(item->>'quantity')::numeric; price:=(item->>'unit_price')::numeric; raw_id:=nullif(item->>'raw_material_id','')::uuid; prod_id:=nullif(item->>'product_id','')::uuid;
    insert into public.purchase_items(purchase_id,raw_material_id,product_id,item_name,quantity,unit_name,unit_price)
    values(pur.id,raw_id,prod_id,btrim(item->>'item_name'),qty,coalesce(nullif(item->>'unit_name',''),'وحدة'),price);
  end loop;
  return pur;
end; $$;

grant execute on function public.create_purchase_draft_v2(uuid,uuid,jsonb,text,numeric,uuid,uuid,numeric,text,text) to authenticated;
revoke execute on function public.create_purchase_draft_v2(uuid,uuid,jsonb,text,numeric,uuid,uuid,numeric,text,text) from anon;
