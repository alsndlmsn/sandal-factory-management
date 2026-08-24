create table if not exists public.role_controls(
 role_id uuid primary key references public.roles(id) on delete cascade,
 data_scope text not null default 'all',
 cash_visibility boolean not null default false,
 can_cash_in boolean not null default false,
 can_cash_out boolean not null default false,
 can_transfer boolean not null default false,
 can_count boolean not null default false,
 can_approve boolean not null default false,
 spend_limit numeric(14,2),
 discount_limit numeric(14,2),
 transfer_limit numeric(14,2),
 adjustment_limit numeric(14,2),
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now()
);
insert into public.role_controls(role_id,data_scope,cash_visibility,can_cash_in,can_cash_out,can_transfer,can_count,can_approve) select id,case when code='manager' then 'all' else 'department' end,code='manager',code='manager',code in('manager','finance'),code in('manager','finance'),code in('manager','finance'),code='manager' from public.roles r on conflict(role_id) do nothing;

create or replace function public.update_role_controls(p_role_id uuid,p_data_scope text,p_cash_visibility boolean,p_can_cash_in boolean,p_can_cash_out boolean,p_can_transfer boolean,p_can_count boolean,p_can_approve boolean,p_spend_limit numeric default null,p_discount_limit numeric default null,p_transfer_limit numeric default null,p_adjustment_limit numeric default null) returns public.role_controls language plpgsql security definer set search_path=public as $$
declare c public.role_controls; mgr boolean;
begin
 select coalesce(is_manager,false) into mgr from public.profiles where id=auth.uid();
 if auth.uid() is null or not coalesce(mgr,false) then raise exception 'تعديل صلاحيات الأدوار متاح للمدير فقط'; end if;
 if p_role_id is null or p_data_scope not in('own','department','all') then raise exception 'بيانات الدور غير صحيحة'; end if;
 insert into public.role_controls(role_id,data_scope,cash_visibility,can_cash_in,can_cash_out,can_transfer,can_count,can_approve,spend_limit,discount_limit,transfer_limit,adjustment_limit,updated_by) values(p_role_id,p_data_scope,p_cash_visibility,p_can_cash_in,p_can_cash_out,p_can_transfer,p_can_count,p_can_approve,p_spend_limit,p_discount_limit,p_transfer_limit,p_adjustment_limit,auth.uid()) on conflict(role_id) do update set data_scope=excluded.data_scope,cash_visibility=excluded.cash_visibility,can_cash_in=excluded.can_cash_in,can_cash_out=excluded.can_cash_out,can_transfer=excluded.can_transfer,can_count=excluded.can_count,can_approve=excluded.can_approve,spend_limit=excluded.spend_limit,discount_limit=excluded.discount_limit,transfer_limit=excluded.transfer_limit,adjustment_limit=excluded.adjustment_limit,updated_by=auth.uid(),updated_at=now() returning * into c;
 return c;
end; $$;
grant select on public.role_controls to authenticated;
grant execute on function public.update_role_controls(uuid,text,boolean,boolean,boolean,boolean,boolean,boolean,numeric,numeric,numeric,numeric) to authenticated;
