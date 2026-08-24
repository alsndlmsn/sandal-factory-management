-- تشديد الوصول إلى الجداول الحساسة والدوال المرفوعة عبر PostgREST.
alter table public.role_controls enable row level security;
alter table public.finance_transfers enable row level security;
alter table public.cash_counts enable row level security;
alter table public.return_refunds enable row level security;

drop policy if exists role_controls_view on public.role_controls;
create policy role_controls_view on public.role_controls for select to authenticated
using (public.current_user_is_manager() or public.current_user_has_permission('users.view'));

drop policy if exists return_refunds_view on public.return_refunds;
create policy return_refunds_view on public.return_refunds for select to authenticated
using (public.current_user_is_manager() or public.current_user_has_permission('returns.view'));

-- كل دوال SECURITY DEFINER في public لا تُستدعى دون جلسة مصادق عليها.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef=true
  loop
    execute format('revoke execute on function %s from anon, public', f.signature);
    execute format('grant execute on function %s to authenticated', f.signature);
  end loop;
end $$;
