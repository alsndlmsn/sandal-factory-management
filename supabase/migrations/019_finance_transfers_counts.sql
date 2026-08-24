create table if not exists public.finance_transfers(
 id uuid primary key default gen_random_uuid(),
 transfer_number text not null unique default ('TR-'||to_char(now(),'YYYYMMDDHH24MISSMS')),
 from_type text not null check(from_type in('cash','bank')),
 from_cash_register_id uuid references public.cash_registers(id),
 from_bank_id uuid references public.banks(id),
 to_type text not null check(to_type in('cash','bank')),
 to_cash_register_id uuid references public.cash_registers(id),
 to_bank_id uuid references public.banks(id),
 amount numeric(14,2) not null check(amount>0),
 notes text,
 status text not null default 'approved',
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create table if not exists public.cash_counts(
 id uuid primary key default gen_random_uuid(),
 cash_register_id uuid not null references public.cash_registers(id),
 expected_amount numeric(14,2) not null,
 counted_amount numeric(14,2) not null,
 variance numeric(14,2) not null,
 notes text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
insert into public.permissions(code,name_ar,module) values('treasury.count','جرد خزنة','finance') on conflict(code) do nothing;

create or replace function public.create_finance_transfer(p_from_type text,p_from_id uuid,p_to_type text,p_to_id uuid,p_amount numeric,p_notes text default null) returns public.finance_transfers language plpgsql security definer set search_path=public as $$
declare t public.finance_transfers; from_cash uuid; from_bank uuid; to_cash uuid; to_bank uuid;
begin
 if auth.uid() is null or not public.current_user_has_permission('treasury.transfer') then raise exception 'غير مصرح بالتحويل الداخلي'; end if;
 if p_amount<=0 or p_from_type not in('cash','bank') or p_to_type not in('cash','bank') then raise exception 'بيانات التحويل غير صحيحة'; end if;
 if p_from_type='cash' then from_cash:=p_from_id; else from_bank:=p_from_id; end if;
 if p_to_type='cash' then to_cash:=p_to_id; else to_bank:=p_to_id; end if;
 if p_from_type=p_to_type and p_from_id=p_to_id then raise exception 'لا يمكن التحويل إلى نفس الحساب'; end if;
 insert into public.finance_transfers(from_type,from_cash_register_id,from_bank_id,to_type,to_cash_register_id,to_bank_id,amount,notes,created_by) values(p_from_type,from_cash,from_bank,p_to_type,to_cash,to_bank,p_amount,p_notes,auth.uid()) returning * into t;
 if p_from_type='cash' then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_from_id,'out','transfer',p_amount,'finance_transfer',t.id,auth.uid(),p_notes); else insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_from_id,'out','transfer',p_amount,'finance_transfer',t.id,auth.uid(),p_notes); end if;
 if p_to_type='cash' then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_to_id,'in','transfer',p_amount,'finance_transfer',t.id,auth.uid(),p_notes); else insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(p_to_id,'in','transfer',p_amount,'finance_transfer',t.id,auth.uid(),p_notes); end if;
 return t;
end; $$;

create or replace function public.record_cash_count(p_cash_register_id uuid,p_counted_amount numeric,p_notes text default null) returns public.cash_counts language plpgsql security definer set search_path=public as $$
declare c public.cash_counts; expected numeric;
begin
 if auth.uid() is null or not public.current_user_has_permission('treasury.count') then raise exception 'غير مصرح بجرد الخزنة'; end if;
 if p_counted_amount<0 then raise exception 'المبلغ الفعلي لا يمكن أن يكون سالبًا'; end if;
 select coalesce(r.opening_balance,0)+coalesce((select sum(case when direction='in' then amount else -amount end) from public.cash_transactions where cash_register_id=r.id),0) into expected from public.cash_registers r where r.id=p_cash_register_id;
 if expected is null then raise exception 'الخزنة غير موجودة'; end if;
 insert into public.cash_counts(cash_register_id,expected_amount,counted_amount,variance,notes,created_by) values(p_cash_register_id,expected,p_counted_amount,p_counted_amount-expected,p_notes,auth.uid()) returning * into c;
 return c;
end; $$;
grant execute on function public.create_finance_transfer(text,uuid,text,uuid,numeric,text) to authenticated;
grant execute on function public.record_cash_count(uuid,numeric,text) to authenticated;
grant select,insert on public.finance_transfers,public.cash_counts to authenticated;
