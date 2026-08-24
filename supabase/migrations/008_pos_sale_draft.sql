create or replace function public.create_sale_draft(
  p_invoice_number text,
  p_warehouse_id uuid,
  p_payment_method public.payment_method,
  p_cash_register_id uuid,
  p_bank_id uuid,
  p_bank_transaction_number text,
  p_customer_name text,
  p_discount numeric,
  p_lines jsonb,
  p_notes text default null
)
returns public.sales
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sales;
  customer_id_value uuid;
  line jsonb;
  subtotal_value numeric := 0;
  product_row public.products;
  quantity_value numeric;
  price_value numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.create') then raise exception 'غير مصرح بإنشاء الفاتورة'; end if;
  if length(btrim(p_invoice_number)) < 2 or p_warehouse_id is null or jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) < 1 then raise exception 'أكمل رقم الفاتورة والمخزن وصنفًا واحدًا على الأقل'; end if;
  if p_discount < 0 then raise exception 'الخصم غير صحيح'; end if;
  if p_payment_method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
  if p_payment_method='bank' and (p_bank_id is null or length(btrim(coalesce(p_bank_transaction_number,''))) < 3) then raise exception 'اختر البنك وأدخل رقم العملية البنكية'; end if;
  if p_customer_name is not null and length(btrim(p_customer_name)) > 0 then
    select id into customer_id_value from public.customers where lower(name)=lower(btrim(p_customer_name)) limit 1;
    if customer_id_value is null then insert into public.customers(name,created_by) values(btrim(p_customer_name),auth.uid()) returning id into customer_id_value; end if;
  end if;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into product_row from public.products where id=(line->>'product_id')::uuid and is_active=true for share;
    if product_row.id is null then raise exception 'الصنف المختار غير موجود'; end if;
    quantity_value := (line->>'quantity')::numeric;
    price_value := coalesce((line->>'unit_price')::numeric,product_row.sale_price);
    if quantity_value <= 0 or price_value < 0 then raise exception 'الكمية أو السعر غير صحيح'; end if;
    subtotal_value := subtotal_value + quantity_value*price_value;
  end loop;
  insert into public.sales(invoice_number,customer_id,warehouse_id,payment_method,cash_register_id,bank_id,bank_transaction_number,subtotal,discount,total,status,notes,created_by)
  values(p_invoice_number,customer_id_value,p_warehouse_id,p_payment_method,p_cash_register_id,p_bank_id,nullif(btrim(p_bank_transaction_number),''),subtotal_value,p_discount,greatest(0,subtotal_value-p_discount),'draft',p_notes,auth.uid()) returning * into s;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into product_row from public.products where id=(line->>'product_id')::uuid;
    quantity_value := (line->>'quantity')::numeric;
    price_value := coalesce((line->>'unit_price')::numeric,product_row.sale_price);
    insert into public.sale_items(sale_id,product_id,quantity,unit_code,unit_price,unit_cost) values(s.id,product_row.id,quantity_value,product_row.unit_code,price_value,product_row.purchase_price);
  end loop;
  return s;
end;
$$;
revoke execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) from public;
revoke execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) from anon;
grant execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) to authenticated;
