create or replace function public.create_stock_movement_draft(p_document_number text,p_direction public.movement_direction,p_movement_type text,p_warehouse_id uuid,p_product_id uuid,p_quantity numeric,p_unit_code text,p_unit_cost numeric,p_notes text default null)
returns public.stock_movements
language plpgsql
security definer
set search_path = public
as $$
declare m public.stock_movements;
begin
  if auth.uid() is null or not public.current_user_has_permission('inventory.create') then raise exception 'غير مصرح بإنشاء حركة المخزن'; end if;
  if length(btrim(p_document_number)) < 2 or p_warehouse_id is null or p_product_id is null or p_quantity <= 0 then raise exception 'أكمل بيانات الحركة والمخزن والصنف والكمية'; end if;
  insert into public.stock_movements(document_number,direction,movement_type,warehouse_id,movement_date,status,notes,created_by) values(p_document_number,p_direction,p_movement_type,p_warehouse_id,now(),'draft',p_notes,auth.uid()) returning * into m;
  insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_code,unit_cost,notes) values(m.id,p_product_id,p_quantity,p_unit_code,p_unit_cost,p_notes);
  return m;
end;
$$;
revoke execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) from public;
revoke execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) from anon;
grant execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) to authenticated;
