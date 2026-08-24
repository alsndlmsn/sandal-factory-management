-- مواءمة نوع الإنتاج مع schema الفعلي؛ كان العمود مفقودًا رغم وجوده في نموذج الواجهة.
alter table public.production_orders add column if not exists order_type text not null default 'stock';

do $$
begin
  if not exists (select 1 from pg_constraint where conname='production_orders_order_type_check') then
    alter table public.production_orders add constraint production_orders_order_type_check check (order_type in ('stock','customer','rework','recycle'));
  end if;
end $$;

create or replace function public.create_production_order_v2(
  p_product_id uuid,p_planned_quantity numeric,p_order_type text,p_source_warehouse_id uuid,p_raw_material_id uuid,p_raw_quantity numeric,p_destination_warehouse_id uuid,p_notes text default null
) returns public.production_orders
language plpgsql security definer set search_path=public as $$
declare po public.production_orders; rm public.raw_materials; kind text;
begin
  if auth.uid() is null or not public.current_user_has_permission('production.create') then raise exception 'غير مصرح بإنشاء أمر إنتاج'; end if;
  if p_product_id is null or coalesce(p_planned_quantity,0)<=0 then raise exception 'اختر المنتج والكمية المخططة'; end if;
  if p_destination_warehouse_id is null then raise exception 'اختر مخزن المنتجات الجاهزة'; end if;
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
  values('PRD-'||lpad(nextval('public.production_seq')::text,6,'0'),p_product_id,current_date,p_planned_quantity,kind,p_source_warehouse_id,p_raw_material_id,coalesce(p_raw_quantity,0),p_destination_warehouse_id,'draft'::document_status,p_notes,auth.uid()) returning * into po;
  if p_raw_material_id is not null then
    insert into public.production_materials(production_order_id,product_id,required_quantity,issued_quantity,raw_material_id)
    values(po.id,p_product_id,p_raw_quantity,0,p_raw_material_id);
  end if;
  return po;
end; $$;

grant execute on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text) to authenticated;
revoke execute on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text) from anon;
