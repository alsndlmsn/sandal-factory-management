-- دعم تاريخ الإنتاج المدخل، وحركات خام يدوية، وعملاء الدفع الآجل.

create sequence if not exists public.customer_seq;

alter table public.customers add column if not exists customer_number text;
alter table public.customers add column if not exists credit_limit numeric(14,2) not null default 0 check (credit_limit >= 0);
alter table public.customers add column if not exists opening_balance numeric(14,2) not null default 0 check (opening_balance >= 0);
alter table public.customers add column if not exists is_active boolean not null default true;

update public.customers
set customer_number='CUS-'||lpad(nextval('public.customer_seq')::text,6,'0')
where customer_number is null;

create or replace function public.create_customer(
  p_name text,
  p_phone text default null,
  p_credit_limit numeric default 0,
  p_opening_balance numeric default 0,
  p_notes text default null
) returns public.customers
language plpgsql security definer set search_path=public as $$
declare c public.customers;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.create') then raise exception 'غير مصرح بإضافة عميل'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'اسم العميل مطلوب'; end if;
  if coalesce(p_credit_limit,0)<0 or coalesce(p_opening_balance,0)<0 then raise exception 'حد الائتمان والرصيد الافتتاحي لا يمكن أن يكونا سالبين'; end if;
  insert into public.customers(customer_number,name,phone,notes,created_by,credit_limit,opening_balance,is_active)
  values('CUS-'||lpad(nextval('public.customer_seq')::text,6,'0'),btrim(p_name),nullif(btrim(p_phone),''),p_notes,auth.uid(),greatest(coalesce(p_credit_limit,0),0),greatest(coalesce(p_opening_balance,0),0),true)
  returning * into c;
  return c;
end; $$;

grant execute on function public.create_customer(text,text,numeric,numeric,text) to authenticated;
revoke execute on function public.create_customer(text,text,numeric,numeric,text) from anon;
grant select on public.customers to authenticated;

-- إعادة إنشاء RPC الإنتاج نفسها مع السماح بإدخال تاريخ الإنتاج، مع إبقاء التوقيع القديم مغلقًا لتجنب الغموض.
drop function if exists public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text);
create or replace function public.create_production_order_v2(
  p_product_id uuid,
  p_planned_quantity numeric,
  p_order_type text,
  p_source_warehouse_id uuid,
  p_raw_material_id uuid,
  p_raw_quantity numeric,
  p_destination_warehouse_id uuid,
  p_notes text default null,
  p_production_date date default current_date
) returns public.production_orders
language plpgsql security definer set search_path=public as $$
declare po public.production_orders; rm public.raw_materials; kind text;
begin
  if auth.uid() is null or not public.current_user_has_permission('production.create') then raise exception 'غير مصرح بإنشاء أمر إنتاج'; end if;
  if p_product_id is null or coalesce(p_planned_quantity,0)<=0 then raise exception 'اختر المنتج والكمية المخططة'; end if;
  if p_destination_warehouse_id is null then raise exception 'اختر مخزن المنتجات الجاهزة'; end if;
  if p_production_date is null then raise exception 'تاريخ الإنتاج مطلوب'; end if;
  kind:=coalesce(nullif(p_order_type,''),'stock');
  if kind not in ('stock','customer','rework','recycle') then raise exception 'نوع الإنتاج غير صحيح'; end if;
  if p_raw_material_id is not null then
    if p_source_warehouse_id is null or coalesce(p_raw_quantity,0)<=0 then raise exception 'اختر مخزن الخام وكمية الخام'; end if;
    select * into rm from public.raw_materials where id=p_raw_material_id and is_active=true;
    if rm.id is null then raise exception 'المادة الخام غير موجودة أو غير نشطة'; end if;
  elsif coalesce(p_raw_quantity,0)>0 or p_source_warehouse_id is not null then
    raise exception 'اختر المادة الخام قبل تحديد المصدر أو الكمية';
  end if;
  insert into public.production_orders(order_number,product_id,production_date,planned_quantity,order_type,source_warehouse_id,raw_material_id,raw_quantity,destination_warehouse_id,status,notes,created_by)
  values('PRD-'||lpad(nextval('public.production_seq')::text,6,'0'),p_product_id,p_production_date,p_planned_quantity,kind,p_source_warehouse_id,p_raw_material_id,coalesce(p_raw_quantity,0),p_destination_warehouse_id,'draft'::document_status,p_notes,auth.uid()) returning * into po;
  if p_raw_material_id is not null then
    insert into public.production_materials(production_order_id,product_id,required_quantity,issued_quantity,raw_material_id)
    values(po.id,p_product_id,p_raw_quantity,0,p_raw_material_id);
  end if;
  return po;
end; $$;

grant execute on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text,date) to authenticated;
revoke execute on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text,date) from anon;

-- مسار خام مستقل للوارد والصادر والتحويل، لأن المسار القديم مخصص للمنتجات.
create or replace function public.create_raw_stock_movement_draft(
  p_direction text,
  p_source_type text,
  p_raw_material_id uuid,
  p_quantity numeric,
  p_unit_name text,
  p_from_warehouse_id uuid default null,
  p_to_warehouse_id uuid default null,
  p_cost_price numeric default 0,
  p_notes text default null
) returns public.stock_movements
language plpgsql security definer set search_path=public as $$
declare m public.stock_movements; r public.raw_materials;
begin
  if auth.uid() is null or not public.current_user_has_permission('inventory.create') then raise exception 'غير مصرح بإنشاء حركة خام'; end if;
  if p_direction not in('in','out','transfer') then raise exception 'نوع الحركة غير صحيح'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'الكمية يجب أن تكون أكبر من صفر'; end if;
  select * into r from public.raw_materials where id=p_raw_material_id and is_active=true;
  if r.id is null then raise exception 'اختر مادة خام نشطة'; end if;
  if p_direction in('in','out') and p_from_warehouse_id is null and p_to_warehouse_id is null then raise exception 'اختر المخزن'; end if;
  if p_direction='transfer' and (p_from_warehouse_id is null or p_to_warehouse_id is null or p_from_warehouse_id=p_to_warehouse_id) then raise exception 'اختر مخزنين مختلفين للتحويل'; end if;
  insert into public.stock_movements(direction,source_type,from_warehouse_id,to_warehouse_id,notes,created_by)
  values(p_direction,coalesce(nullif(p_source_type,''),'manual_raw'),p_from_warehouse_id,p_to_warehouse_id,p_notes,auth.uid()) returning * into m;
  insert into public.stock_movement_lines(movement_id,raw_material_id,quantity,unit_name,cost_price,notes)
  values(m.id,p_raw_material_id,p_quantity,coalesce(nullif(p_unit_name,''),r.unit_name),greatest(coalesce(p_cost_price,0),0),p_notes);
  return m;
end; $$;

grant execute on function public.create_raw_stock_movement_draft(text,text,uuid,numeric,text,uuid,uuid,numeric,text) to authenticated;
revoke execute on function public.create_raw_stock_movement_draft(text,text,uuid,numeric,text,uuid,uuid,numeric,text) from anon;

-- اعتماد حركة المخزون مع فحص رصيد المنتج أو المادة الخام حسب السطر.
create or replace function public.approve_stock_movement(p_movement_id uuid)
returns public.stock_movements
language plpgsql security definer set search_path=public as $$
declare m public.stock_movements; it record; balance numeric; warehouse uuid;
begin
  if auth.uid() is null or not public.current_user_has_permission('inventory.approve') then raise exception 'غير مصرح باعتماد حركة المخزون'; end if;
  select * into m from public.stock_movements where id=p_movement_id for update;
  if m.id is null then raise exception 'الحركة غير موجودة'; end if;
  if m.status<>'draft' then raise exception 'الحركة اعتمدت أو ألغيت سابقًا'; end if;
  warehouse:=m.from_warehouse_id;
  if m.direction in('out','transfer') then
    for it in select product_id,raw_material_id,quantity from public.stock_movement_lines where movement_id=m.id loop
      if it.product_id is not null then
        select coalesce(sum(case when sm.direction='in' then sml.quantity when sm.direction='out' then -sml.quantity when sm.direction='transfer' and sm.to_warehouse_id=warehouse then sml.quantity when sm.direction='transfer' and sm.from_warehouse_id=warehouse then -sml.quantity else 0 end),0)
        into balance from public.stock_movement_lines sml join public.stock_movements sm on sm.id=sml.movement_id
        where sml.product_id=it.product_id and sm.status='approved' and (sm.from_warehouse_id=warehouse or sm.to_warehouse_id=warehouse);
      elsif it.raw_material_id is not null then
        select coalesce(sum(case when sm.direction='in' then sml.quantity when sm.direction='out' then -sml.quantity when sm.direction='transfer' and sm.to_warehouse_id=warehouse then sml.quantity when sm.direction='transfer' and sm.from_warehouse_id=warehouse then -sml.quantity else 0 end),0)
        into balance from public.stock_movement_lines sml join public.stock_movements sm on sm.id=sml.movement_id
        where sml.raw_material_id=it.raw_material_id and sm.status='approved' and (sm.from_warehouse_id=warehouse or sm.to_warehouse_id=warehouse);
      else
        raise exception 'سطر حركة المخزون بلا منتج أو خام';
      end if;
      if balance<it.quantity then raise exception 'الرصيد المتاح لا يكفي للحركة'; end if;
    end loop;
  end if;
  update public.stock_movements set status='approved',approved_by=auth.uid(),approved_at=now() where id=m.id returning * into m;
  return m;
end; $$;

grant execute on function public.approve_stock_movement(uuid) to authenticated;
revoke execute on function public.approve_stock_movement(uuid) from anon;
