-- Supabase REST access requires SQL grants in addition to RLS policies.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select on public.v_stock_balances, public.v_cash_balances to authenticated;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
