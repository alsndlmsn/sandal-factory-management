alter table public.production_orders add column if not exists destination_warehouse_id uuid references public.warehouses(id);
alter table public.production_materials add column if not exists raw_material_id uuid references public.raw_materials(id);
insert into public.permissions(code,name_ar,module) values('production.approve','اعتماد أمر إنتاج','production') on conflict(code) do nothing;

create or replace function public.approve_production_order(p_order_id uuid,p_actual_quantity numeric,p_accepted_quantity numeric,p_damaged_quantity numeric,p_destination_warehouse_id uuid default null) returns public.production_orders language plpgsql security definer set search_path=public as $$
declare po public.production_orders; mov public.stock_movements; dest uuid; accepted numeric:=greatest(coalesce(p_accepted_quantity,0),0); damaged numeric:=greatest(coalesce(p_damaged_quantity,0),0); actual numeric:=greatest(coalesce(p_actual_quantity,0),0);
begin
 if auth.uid() is null or not public.current_user_has_permission('production.approve') then raise exception 'غير مصرح باعتماد الإنتاج'; end if;
 select * into po from public.production_orders where id=p_order_id for update;
 if po.id is null then raise exception 'أمر الإنتاج غير موجود'; end if;
 if po.status::text<>'draft' then raise exception 'أمر الإنتاج اعتمد أو أُلغي سابقًا'; end if;
 if actual<=0 or accepted<0 or damaged<0 or accepted+damaged<>actual then raise exception 'يجب أن يساوي المقبول والتالف الإنتاج الفعلي'; end if;
 dest:=coalesce(p_destination_warehouse_id,po.destination_warehouse_id);
 if accepted>0 and dest is null then raise exception 'اختر مخزن المنتجات الجاهزة'; end if;
 if accepted>0 then
  insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at,notes) values('in','production',po.id,dest,'approved',auth.uid(),auth.uid(),now(),'ناتج إنتاج معتمد') returning * into mov;
  insert into public.stock_movement_lines(movement_id,product_id,quantity,cost_price,notes) select mov.id,po.product_id,accepted,p.cost_price,'ناتج أمر '||po.order_number from public.products p where p.id=po.product_id;
 end if;
 if damaged>0 then insert into public.damaged_goods(product_id,quantity,source_type,source_id,reason,status,notes,created_by) values(po.product_id,damaged,'production',po.id,'تالف إنتاج','pending','أمر إنتاج '||po.order_number,auth.uid()); end if;
 update public.production_orders set actual_quantity=actual,accepted_quantity=accepted,damaged_quantity=damaged,destination_warehouse_id=dest,status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=po.id returning * into po;
 return po;
end; $$;
grant execute on function public.approve_production_order(uuid,numeric,numeric,numeric,uuid) to authenticated;
grant select,insert,update on public.production_orders,public.production_materials,public.damaged_goods to authenticated;
