-- تصحيح امتيازات الدوال الجديدة: التنفيذ للمستخدمين المصادقين فقط.
revoke all on function public.create_customer(text,text,numeric,numeric,text) from public;
revoke all on function public.create_customer(text,text,numeric,numeric,text) from anon;
grant execute on function public.create_customer(text,text,numeric,numeric,text) to authenticated;

revoke all on function public.create_raw_stock_movement_draft(text,text,uuid,numeric,text,uuid,uuid,numeric,text) from public;
revoke all on function public.create_raw_stock_movement_draft(text,text,uuid,numeric,text,uuid,uuid,numeric,text) from anon;
grant execute on function public.create_raw_stock_movement_draft(text,text,uuid,numeric,text,uuid,uuid,numeric,text) to authenticated;

revoke all on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text,date) from public;
revoke all on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text,date) from anon;
grant execute on function public.create_production_order_v2(uuid,numeric,text,uuid,uuid,numeric,uuid,text,date) to authenticated;

revoke all on function public.approve_stock_movement(uuid) from public;
revoke all on function public.approve_stock_movement(uuid) from anon;
grant execute on function public.approve_stock_movement(uuid) to authenticated;
