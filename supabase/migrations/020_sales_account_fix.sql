create or replace function public.create_sale_draft(p_invoice_type text,p_customer_name text,p_customer_id uuid,p_warehouse_id uuid,p_items jsonb,p_discount_type text default 'amount',p_discount_value numeric default 0,p_crafting_fee numeric default 0,p_vat_enabled boolean default false,p_vat_rate numeric default 0,p_payments jsonb default '[]'::jsonb,p_notes text default null) returns public.sales language plpgsql security definer set search_path=public as $$
declare s public.sales; item jsonb; prod public.products; sub numeric:=0; disc numeric:=0; vat numeric:=0; total numeric:=0; paid numeric:=0; qty numeric; price numeric; line numeric; pay jsonb; method text; cash_id_local uuid; bank_id_local uuid; pay_amount numeric;
begin
 if auth.uid() is null or not public.current_user_has_permission('sales.create') then raise exception 'غير مصرح بإنشاء فاتورة'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'أضف منتجًا واحدًا على الأقل'; end if;
 if p_warehouse_id is null then raise exception 'اختر المخزن'; end if;
 insert into public.sales(invoice_type,customer_id,customer_name,warehouse_id,discount_type,discount_value,crafting_fee,vat_enabled,vat_rate,payment_method,notes,created_by) values(coalesce(nullif(p_invoice_type,''),'sale'),p_customer_id,coalesce(nullif(btrim(p_customer_name),''),'عميل عادي'),p_warehouse_id,coalesce(nullif(p_discount_type,''),'amount'),greatest(p_discount_value,0),greatest(p_crafting_fee,0),coalesce(p_vat_enabled,false),greatest(p_vat_rate,0),'unpaid',p_notes,auth.uid()) returning * into s;
 for item in select value from jsonb_array_elements(p_items) loop
  select * into prod from public.products where id=(item->>'product_id')::uuid and is_active=true;
  if prod.id is null then raise exception 'المنتج غير موجود أو غير نشط'; end if;
  qty:=greatest(coalesce((item->>'quantity')::numeric,0),0); if qty<=0 then raise exception 'الكمية يجب أن تكون أكبر من صفر'; end if;
  price:=coalesce(nullif(item->>'unit_price','')::numeric,prod.sale_price); line:=qty*price; sub:=sub+line;
  insert into public.sale_items(sale_id,product_id,product_name,quantity,unit_price,cost_price,line_total) values(s.id,prod.id,prod.name,qty,price,prod.cost_price,line);
 end loop;
 disc:=case when s.discount_type='percent' then sub*least(s.discount_value,100)/100 else least(s.discount_value,sub) end;
 vat:=case when s.vat_enabled then greatest(sub-disc+s.crafting_fee,0)*s.vat_rate/100 else 0 end;
 total:=greatest(sub-disc+s.crafting_fee+vat,0);
 if p_payments is not null then for pay in select value from jsonb_array_elements(p_payments) loop
   pay_amount:=greatest(coalesce(nullif(pay->>'amount','')::numeric,0),0); method:=coalesce(nullif(pay->>'payment_method',''),'cash'); cash_id_local:=nullif(pay->>'cash_register_id','')::uuid; bank_id_local:=nullif(pay->>'bank_id','')::uuid;
   if pay_amount>0 and method in('cash','partial_cash') and cash_id_local is null then raise exception 'اختر خزنة لدفعة الكاش'; end if;
   if pay_amount>0 and method in('bank','partial_bank') and bank_id_local is null then raise exception 'اختر بنكًا للدفعة البنكية'; end if;
   paid:=paid+pay_amount;
   insert into public.sale_payments(sale_id,amount,payment_method,cash_register_id,bank_id,reference,created_by) values(s.id,pay_amount,method,cash_id_local,bank_id_local,nullif(pay->>'reference',''),auth.uid());
   if s.cash_register_id is null and cash_id_local is not null then update public.sales set cash_register_id=cash_id_local where id=s.id; s.cash_register_id:=cash_id_local; end if;
   if s.bank_id is null and bank_id_local is not null then update public.sales set bank_id=bank_id_local where id=s.id; s.bank_id:=bank_id_local; end if;
 end loop; end if;
 if paid>total then raise exception 'إجمالي المدفوع أكبر من قيمة الفاتورة'; end if;
 update public.sales set subtotal=sub,discount_amount=disc,vat_amount=vat,total=total,paid_amount=paid,remaining_amount=greatest(total-paid,0),payment_method=case when paid=0 then 'unpaid' when paid<total then 'partial' else coalesce((select sp.payment_method from public.sale_payments sp where sp.sale_id=s.id and sp.amount>0 order by sp.id limit 1),'cash') end where id=s.id returning * into s;
 return s;
end; $$;

create or replace function public.add_sale_payment(p_sale_id uuid,p_amount numeric,p_payment_method text,p_cash_register_id uuid default null,p_bank_id uuid default null,p_reference text default null) returns public.sales language plpgsql security definer set search_path=public as $$
declare s public.sales; due numeric; method text; final_method text;
begin
 if auth.uid() is null or not public.current_user_has_permission('sales.create') then raise exception 'غير مصرح بإضافة دفعة'; end if;
 select * into s from public.sales where id=p_sale_id for update;
 if s.id is null or s.status<>'approved' then raise exception 'الفاتورة غير موجودة أو غير معتمدة'; end if;
 due:=greatest(coalesce(s.total,0)-coalesce(s.paid_amount,0),0);
 if p_amount<=0 or p_amount>due then raise exception 'قيمة الدفعة أكبر من المتبقي أو غير صحيحة'; end if;
 method:=coalesce(nullif(p_payment_method,''),'cash');
 if method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
 if method='bank' and p_bank_id is null then raise exception 'اختر البنك'; end if;
 insert into public.sale_payments(sale_id,amount,payment_method,cash_register_id,bank_id,reference,created_by) values(s.id,p_amount,method,p_cash_register_id,p_bank_id,p_reference,auth.uid());
 if method='cash' then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,reference,created_by,notes) values(p_cash_register_id,'in','sale_payment',p_amount,'sale',s.id,p_reference,auth.uid(),'دفعة لاحقة لفاتورة'); else insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,reference,created_by,notes) values(p_bank_id,'in','sale_payment',p_amount,'sale',s.id,p_reference,auth.uid(),'دفعة لاحقة لفاتورة'); end if;
 final_method:=case when method='cash' then 'cash' else 'bank' end;
 update public.sales set paid_amount=coalesce(paid_amount,0)+p_amount,remaining_amount=greatest(total-(coalesce(paid_amount,0)+p_amount),0),payment_method=case when greatest(total-(coalesce(paid_amount,0)+p_amount),0)=0 then final_method else 'partial' end where id=s.id returning * into s;
 return s;
end; $$;
grant execute on function public.create_sale_draft(text,text,uuid,uuid,jsonb,text,numeric,numeric,boolean,numeric,jsonb,text) to authenticated;
grant execute on function public.add_sale_payment(uuid,numeric,text,uuid,uuid,text) to authenticated;
