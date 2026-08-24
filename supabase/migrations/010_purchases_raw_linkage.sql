alter table public.stock_movement_lines add column if not exists raw_material_id uuid references public.raw_materials(id);
alter table public.purchases add column if not exists warehouse_id uuid references public.warehouses(id);
alter table public.purchases add column if not exists cash_register_id uuid references public.cash_registers(id);
alter table public.purchases add column if not exists bank_id uuid references public.banks(id);

insert into public.permissions(code,name_ar,module) values
('raw_materials.create','إضافة مادة خام','purchases'),
('purchases.approve','اعتماد شراء','purchases') on conflict(code) do nothing;

create or replace function public.create_raw_material(p_name text,p_unit_name text default null,p_code text default null,p_notes text default null) returns public.raw_materials language plpgsql security definer set search_path=public as $$
declare r public.raw_materials;
begin
 if auth.uid() is null or not public.current_user_has_permission('raw_materials.create') then raise exception 'غير مصرح بإضافة خامة'; end if;
 if nullif(btrim(p_name),'') is null then raise exception 'اسم المادة الخام مطلوب'; end if;
 insert into public.raw_materials(name,unit_name,code,notes,created_by) values(btrim(p_name),nullif(btrim(p_unit_name),''),nullif(btrim(p_code),''),p_notes,auth.uid()) returning * into r;
 return r;
end; $$;

drop function if exists public.create_purchase_draft_v2(uuid,uuid,jsonb,text,numeric,uuid,uuid,numeric,text,text);
create or replace function public.create_purchase_draft_v2(p_supplier_id uuid,p_warehouse_id uuid,p_items jsonb,p_payment_method text default 'credit',p_paid_amount numeric default 0,p_cash_register_id uuid default null,p_bank_id uuid default null,p_discount numeric default 0,p_supplier_invoice text default null,p_notes text default null) returns public.purchases language plpgsql security definer set search_path=public as $$
declare pur public.purchases; item jsonb; item_total numeric:=0; qty numeric; price numeric; item_name text; raw_id uuid; prod_id uuid;
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
 insert into public.purchases(supplier_id,warehouse_id,total,discount,paid_amount,remaining_amount,payment_method,cash_register_id,bank_id,supplier_invoice,notes,created_by) values(p_supplier_id,p_warehouse_id,item_total,greatest(coalesce(p_discount,0),0),least(greatest(coalesce(p_paid_amount,0),0),item_total),greatest(item_total-least(greatest(coalesce(p_paid_amount,0),0),item_total),0),coalesce(nullif(p_payment_method,''),'credit'),p_cash_register_id,p_bank_id,p_supplier_invoice,p_notes,auth.uid()) returning * into pur;
 for item in select value from jsonb_array_elements(p_items) loop
   qty:=(item->>'quantity')::numeric; price:=(item->>'unit_price')::numeric; raw_id:=nullif(item->>'raw_material_id','')::uuid; prod_id:=nullif(item->>'product_id','')::uuid;
   insert into public.purchase_items(purchase_id,raw_material_id,product_id,item_name,quantity,unit_name,unit_price,total) values(pur.id,raw_id,prod_id,btrim(item->>'item_name'),qty,item->>'unit_name',price,qty*price);
 end loop;
 return pur;
end; $$;

create or replace function public.approve_purchase(p_purchase_id uuid) returns public.purchases language plpgsql security definer set search_path=public as $$
declare pur public.purchases; item record; mov public.stock_movements;
begin
 if auth.uid() is null or not public.current_user_has_permission('purchases.approve') then raise exception 'غير مصرح باعتماد الشراء'; end if;
 select * into pur from public.purchases where id=p_purchase_id for update;
 if pur.id is null then raise exception 'فاتورة الشراء غير موجودة'; end if;
 if pur.status<>'draft' then raise exception 'فاتورة الشراء اعتمدت أو ألغيت سابقًا'; end if;
 insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at) values('in','purchase',pur.id,pur.warehouse_id,'approved',auth.uid(),auth.uid(),now()) returning * into mov;
 for item in select * from public.purchase_items where purchase_id=pur.id loop
   insert into public.stock_movement_lines(movement_id,product_id,raw_material_id,quantity,unit_name,cost_price,notes) values(mov.id,item.product_id,item.raw_material_id,item.quantity,item.unit_name,item.unit_price,'شراء '||pur.purchase_number);
 end loop;
 if pur.paid_amount>0 and pur.payment_method='cash' then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(pur.cash_register_id,'out','purchase',pur.paid_amount,'purchase',pur.id,auth.uid(),'سداد شراء '||pur.purchase_number); end if;
 if pur.paid_amount>0 and pur.payment_method='bank' then insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(pur.bank_id,'out','purchase',pur.paid_amount,'purchase',pur.id,auth.uid(),'سداد شراء '||pur.purchase_number); end if;
 update public.purchases set status='approved',approved_by=auth.uid(),approved_at=now() where id=pur.id returning * into pur;
 return pur;
end; $$;

grant execute on function public.create_raw_material(text,text,text,text) to authenticated;
grant execute on function public.create_purchase_draft_v2(uuid,uuid,jsonb,text,numeric,uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.approve_purchase(uuid) to authenticated;
grant select,insert,update on public.raw_materials,public.purchase_items,public.purchases,public.stock_movement_lines to authenticated;
