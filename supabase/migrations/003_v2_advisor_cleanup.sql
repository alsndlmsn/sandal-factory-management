-- Final advisor cleanup: only authenticated callers may reach application RPCs.
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
grant execute on function public.current_user_has_permission(text) to authenticated;
grant execute on function public.current_user_is_manager() to authenticated;
grant execute on function public.stock_balance(uuid,uuid) to authenticated;
grant execute on function public.manager_dashboard_summary() to authenticated;
grant execute on function public.approve_sale(uuid) to authenticated;
grant execute on function public.approve_stock_movement(uuid) to authenticated;
grant execute on function public.approve_expense(uuid) to authenticated;
grant execute on function public.record_cash_transaction(text,uuid,public.movement_direction,text,numeric,text) to authenticated;
grant execute on function public.approve_production_order(uuid) to authenticated;
grant execute on function public.correct_attendance(uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.approve_payroll_period(uuid) to authenticated;
create schema if not exists extensions;
do $$ begin
  if exists (select 1 from pg_extension where extname='citext') then execute 'alter extension citext set schema extensions'; end if;
exception when others then null;
end $$;
