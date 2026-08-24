-- إصلاح الاستدعاء القديم للإنتاج مع الإبقاء على v2 كالمسار الأساسي.
create or replace function public.create_production_order(
  p_product_id uuid,p_planned_quantity numeric,p_order_type text,p_destination uuid,p_notes text default null
) returns public.production_orders
language plpgsql security definer set search_path=public as $$
declare po public.production_orders;
begin
  if auth.uid() is null or not public.current_user_has_permission('production.create') then raise exception 'غير مصرح بإنشاء أمر إنتاج'; end if;
  if p_product_id is null or coalesce(p_planned_quantity,0)<=0 then raise exception 'اختر المنتج والكمية'; end if;
  insert into public.production_orders(product_id,production_date,planned_quantity,order_type,destination_warehouse_id,status,notes,created_by)
  values(p_product_id,current_date,p_planned_quantity,coalesce(nullif(p_order_type,''),'stock'),p_destination,'draft',p_notes,auth.uid()) returning * into po;
  return po;
end; $$;

grant execute on function public.create_production_order(uuid,numeric,text,uuid,text) to authenticated;
revoke execute on function public.create_production_order(uuid,numeric,text,uuid,text) from anon;
