create table if not exists public.employee_incentives (
  id uuid primary key default gen_random_uuid(),
  batch_number text not null,
  employee_id uuid not null references public.employees(id) on delete restrict,
  title text not null,
  amount numeric(18,2) not null check (amount > 0),
  incentive_date date not null default current_date,
  payroll_period_id uuid references public.payroll_periods(id) on delete set null,
  notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_employee_incentives_employee_date on public.employee_incentives(employee_id,incentive_date desc);
alter table public.employee_incentives enable row level security;
drop policy if exists incentives_read on public.employee_incentives;
create policy incentives_read on public.employee_incentives for select to authenticated using (public.current_user_has_permission('payroll.view'));
drop policy if exists incentives_create on public.employee_incentives;
create policy incentives_create on public.employee_incentives for insert to authenticated with check (public.current_user_has_permission('payroll.manage') and created_by=auth.uid());
drop policy if exists incentives_manage on public.employee_incentives;
create policy incentives_manage on public.employee_incentives for update to authenticated using (public.current_user_has_permission('payroll.manage')) with check (public.current_user_has_permission('payroll.manage'));
grant select,insert,update on public.employee_incentives to authenticated;

create or replace function public.prepare_payroll_period(p_period_id uuid)
returns setof public.payroll_records
language plpgsql
security definer
set search_path = public
as $$
declare
  period_row public.payroll_periods;
  e record;
  r public.payroll_records;
  basic numeric;
  bonus numeric;
  outstanding numeric;
  advance_part numeric;
  attended_days numeric;
  worked_hours numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح بإعداد المرتبات'; end if;
  select * into period_row from public.payroll_periods where id=p_period_id for update;
  if period_row.id is null or period_row.status not in ('draft','pending') then raise exception 'فترة المرتبات غير قابلة للإعداد'; end if;
  for e in select * from public.employees where status='active' and employment_date <= period_row.period_end order by full_name loop
    select count(*)::numeric into attended_days from public.attendance_records a where a.employee_id=e.id and a.check_in_at is not null and (a.check_in_at at time zone 'Africa/Khartoum')::date between period_row.period_start and period_row.period_end and a.status in ('present','late','half_day');
    select coalesce(sum(coalesce(a.working_minutes,0))/60.0,0) into worked_hours from public.attendance_records a where a.employee_id=e.id and a.check_in_at is not null and (a.check_in_at at time zone 'Africa/Khartoum')::date between period_row.period_start and period_row.period_end;
    basic := case when e.wage_type='monthly' then e.base_salary when e.wage_type='daily' then e.base_salary*attended_days else e.base_salary*worked_hours end;
    select coalesce(sum(i.amount),0) into bonus from public.employee_incentives i where i.employee_id=e.id and i.incentive_date between period_row.period_start and period_row.period_end and (i.payroll_period_id is null or i.payroll_period_id=p_period_id);
    select coalesce(sum(a.amount-a.deducted_amount),0) into outstanding from public.employee_advances a where a.employee_id=e.id and a.advance_date::date <= period_row.period_end and a.deducted_amount < a.amount;
    advance_part := least(outstanding,greatest(0,basic+bonus));
    insert into public.payroll_records(payroll_period_id,employee_id,basic_salary,bonuses,advances_deducted,payment_status)
    values(p_period_id,e.id,basic,bonus,advance_part,'draft')
    on conflict(payroll_period_id,employee_id) do update set basic_salary=excluded.basic_salary,bonuses=excluded.bonuses,advances_deducted=excluded.advances_deducted
    returning * into r;
    update public.employee_incentives set payroll_period_id=p_period_id where employee_id=e.id and incentive_date between period_row.period_start and period_row.period_end and (payroll_period_id is null or payroll_period_id=p_period_id);
    return next r;
  end loop;
end;
$$;
revoke execute on function public.prepare_payroll_period(uuid) from public;
revoke execute on function public.prepare_payroll_period(uuid) from anon;
grant execute on function public.prepare_payroll_period(uuid) to authenticated;

create or replace function public.approve_payroll_period(p_period_id uuid) returns public.payroll_periods language plpgsql security definer set search_path = public as $$
declare
  p public.payroll_periods;
  pr record;
  adv record;
  remaining numeric;
  take_amount numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح باعتماد المرتبات'; end if;
  update public.payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_period_id and status='draft' returning * into p;
  if p.id is null then raise exception 'فترة المرتبات غير قابلة للاعتماد'; end if;
  for pr in select * from public.payroll_records where payroll_period_id=p_period_id for update loop
    remaining := pr.advances_deducted;
    for adv in select * from public.employee_advances where employee_id=pr.employee_id and advance_date::date <= p.period_end and deducted_amount < amount order by advance_date,created_at for update loop
      exit when remaining <= 0;
      take_amount := least(remaining,adv.amount-adv.deducted_amount);
      update public.employee_advances set deducted_amount=deducted_amount+take_amount where id=adv.id;
      remaining := remaining-take_amount;
    end loop;
  end loop;
  return p;
end;
$$;
revoke execute on function public.approve_payroll_period(uuid) from public;
revoke execute on function public.approve_payroll_period(uuid) from anon;
grant execute on function public.approve_payroll_period(uuid) to authenticated;
