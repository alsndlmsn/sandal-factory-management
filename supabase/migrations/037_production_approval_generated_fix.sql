-- إصلاح اعتماد الإنتاج وفق schema الفعلي.
-- accepted_quantity عمود generated، فلا يُكتب يدويًا. كما أن سطر صرف الخام يجب ألا يحمل product_id النهائي.
create or replace function public.approve_production_order(
  p_order_id uuid,p_actual_quantity numeric,p_accepted_quantity numeric,p_damaged_quantity numeric,p_destination_warehouse_id uuid default null
) returns public.production_orders
language plpgsql security definer set search_path=public as $$
declare
  po public.production_orders;
  mov public.stock_movements;
  raw_mov public.stock_movements;
  dest uuid;
  accepted numeric:=greatest(coalesce(p_accepted_quantity,0),0);
  damaged numeric:=greatest(coalesce(p_damaged_quantity,0),0);
  actual numeric:=greatest(coalesce(p_actual_quantity,0),0);
  available numeric;
  raw_cost numeric:=0;
begin
  if auth.uid() is null or not public.current_user_has_permission('production.approve') then raise exception 'غير مصرح باعتماد الإنتاج'; end if;
  select * into po from public.production_orders where id=p_order_id for update;
  if po.id is null then raise exception 'أمر الإنتاج غير موجود'; end if;
  if po.status::text not in ('draft','planned') then raise exception 'أمر الإنتاج اعتمد أو أُلغي سابقًا'; end if;
  if actual<=0 or accepted<0 or damaged<0 or accepted+damaged<>actual then raise exception 'يجب أن يساوي المقبول والتالف الإنتاج الفعلي'; end if;
  dest:=coalesce(p_destination_warehouse_id,po.destination_warehouse_id);
  if accepted>0 and dest is null then raise exception 'اختر مخزن المنتجات الجاهزة'; end if;
  if po.raw_material_id is not null and po.raw_quantity>0 then
    if po.source_warehouse_id is null then raise exception 'مخزن الخام غير محدد'; end if;
    select coalesce(sum(case when sm.direction='in' then sml.quantity when sm.direction='out' then -sml.quantity when sm.direction='transfer' and sm.to_warehouse_id=po.source_warehouse_id then sml.quantity when sm.direction='transfer' and sm.from_warehouse_id=po.source_warehouse_id then -sml.quantity else 0 end),0)
      into available
      from public.stock_movement_lines sml join public.stock_movements sm on sm.id=sml.movement_id
      where sml.raw_material_id=po.raw_material_id and sm.status='approved' and (sm.from_warehouse_id=po.source_warehouse_id or sm.to_warehouse_id=po.source_warehouse_id);
    if available<po.raw_quantity then raise exception 'رصيد الخام في المخزن المحدد لا يكفي'; end if;
    select coalesce(sum(sml.quantity*sml.cost_price)/nullif(sum(sml.quantity),0),0)
      into raw_cost
      from public.stock_movement_lines sml join public.stock_movements sm on sm.id=sml.movement_id
      where sml.raw_material_id=po.raw_material_id and sm.direction='in' and sm.status='approved' and sm.to_warehouse_id=po.source_warehouse_id;
    insert into public.stock_movements(direction,source_type,source_id,from_warehouse_id,status,created_by,approved_by,approved_at,notes)
    values('out','production',po.id,po.source_warehouse_id,'approved',auth.uid(),auth.uid(),now(),'صرف خام لأمر الإنتاج') returning * into raw_mov;
    insert into public.stock_movement_lines(movement_id,product_id,raw_material_id,quantity,unit_name,cost_price,notes)
    select raw_mov.id,null,po.raw_material_id,po.raw_quantity,rm.unit_name,coalesce(raw_cost,0),'صرف خام لأمر '||po.order_number from public.raw_materials rm where rm.id=po.raw_material_id;
    update public.production_materials set issued_quantity=po.raw_quantity where production_order_id=po.id and raw_material_id=po.raw_material_id;
  end if;
  if accepted>0 then
    insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at,notes)
    values('in','production',po.id,dest,'approved',auth.uid(),auth.uid(),now(),'ناتج إنتاج معتمد') returning * into mov;
    insert into public.stock_movement_lines(movement_id,product_id,quantity,cost_price,notes)
    select mov.id,po.product_id,accepted,p.cost_price,'ناتج أمر '||po.order_number from public.products p where p.id=po.product_id;
  end if;
  if damaged>0 then
    insert into public.damaged_goods(product_id,quantity,source_type,source_id,reason,status,notes,created_by)
    values(po.product_id,damaged,'production',po.id,'تالف إنتاج','pending','أمر إنتاج '||po.order_number,auth.uid());
  end if;
  insert into public.production_outputs(production_order_id,product_id,accepted_quantity,damaged_quantity)
  values(po.id,po.product_id,accepted,damaged);
  -- accepted_quantity مولّد من actual_quantity - damaged_quantity.
  update public.production_orders
    set actual_quantity=actual,damaged_quantity=damaged,destination_warehouse_id=dest,status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
    where id=po.id returning * into po;
  return po;
end; $$;

grant execute on function public.approve_production_order(uuid,numeric,numeric,numeric,uuid) to authenticated;
revoke execute on function public.approve_production_order(uuid,numeric,numeric,numeric,uuid) from anon;
