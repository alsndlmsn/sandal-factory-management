-- دفتر اليومية، دليل الحسابات، القوائم المالية، والتسوية البنكية.
create sequence if not exists public.journal_seq start 1;

create table if not exists public.chart_accounts(
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name_ar text not null,
  account_type text not null check(account_type in('asset','liability','equity','revenue','expense')),
  normal_side text not null check(normal_side in('debit','credit')),
  parent_id uuid references public.chart_accounts(id),
  is_active boolean not null default true,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.journal_entries(
  id uuid primary key default gen_random_uuid(),
  entry_number text unique not null default ('JRN-'||lpad(nextval('public.journal_seq')::text,6,'0')),
  entry_date date not null default current_date,
  description text not null,
  source_type text,
  source_id uuid,
  status text not null default 'posted' check(status in('posted','void')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index if not exists journal_entries_source_uidx on public.journal_entries(source_type,source_id) where source_type is not null and source_id is not null;

create table if not exists public.journal_lines(
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid not null references public.chart_accounts(id),
  description text,
  debit numeric(14,2) not null default 0 check(debit>=0),
  credit numeric(14,2) not null default 0 check(credit>=0),
  check((debit>0 and credit=0) or (credit>0 and debit=0)
));

create table if not exists public.bank_statement_lines(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references public.banks(id),
  statement_date date not null default current_date,
  reference text,
  description text,
  amount numeric(14,2) not null check(amount>0),
  direction text not null check(direction in('in','out')),
  bank_transaction_id uuid references public.bank_transactions(id),
  reconciled boolean not null default false,
  reconciled_at timestamptz,
  reconciled_by uuid references public.profiles(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

insert into public.chart_accounts(code,name_ar,account_type,normal_side) values
 ('1000','الخزائن النقدية','asset','debit'),
 ('1010','الحسابات البنكية','asset','debit'),
 ('1100','العملاء والذمم المدينة','asset','debit'),
 ('1200','مخزون المنتجات','asset','debit'),
 ('1210','مخزون المواد الخام','asset','debit'),
 ('1220','مخزون المنتجات التامة','asset','debit'),
 ('1300','سلف العاملين','asset','debit'),
 ('2000','الموردون والدائنون','liability','credit'),
 ('2100','رواتب مستحقة','liability','credit'),
 ('2200','ضريبة قيمة مضافة مستحقة','liability','credit'),
 ('3000','رأس المال والرصيد الافتتاحي','equity','credit'),
 ('3100','أرباح محتجزة','equity','credit'),
 ('4000','المبيعات','revenue','credit'),
 ('4100','إيرادات أخرى وفروق موجبة','revenue','credit'),
 ('5000','تكلفة البضاعة المباعة','expense','debit'),
 ('5100','تكلفة الإنتاج','expense','debit'),
 ('6000','مصروفات تشغيلية','expense','debit'),
 ('6100','رواتب وأجور','expense','debit'),
 ('6200','حوافز العاملين','expense','debit'),
 ('6300','فروق خزائن سالبة وتالف','expense','debit')
on conflict(code) do update set name_ar=excluded.name_ar,account_type=excluded.account_type,normal_side=excluded.normal_side;

insert into public.permissions(code,name_ar,module) values
 ('journal.view','عرض دفتر اليومية','finance'),
 ('reports.financial','القوائم المالية','finance'),
 ('treasury.reconcile','التسوية البنكية','finance')
on conflict(code) do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='finance' and p.code in('journal.view','reports.financial','treasury.reconcile')
on conflict do nothing;

create or replace function public.account_id(p_code text) returns uuid
language sql stable security definer set search_path=public as $$ select id from public.chart_accounts where code=p_code limit 1 $$;

create or replace function public.post_journal(p_source_type text,p_source_id uuid,p_entry_date date,p_description text,p_created_by uuid,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare e_id uuid; line jsonb; debit_total numeric:=0; credit_total numeric:=0; account uuid;
begin
  if p_source_id is not null then
    select id into e_id from public.journal_entries where source_type=p_source_type and source_id=p_source_id limit 1;
    if e_id is not null then return e_id; end if;
  end if;
  select coalesce(sum(greatest(coalesce((x->>'debit')::numeric,0),0)),0),coalesce(sum(greatest(coalesce((x->>'credit')::numeric,0),0)),0)
    into debit_total,credit_total from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) x;
  if jsonb_array_length(coalesce(p_lines,'[]'::jsonb))<2 or abs(debit_total-credit_total)>0.01 then raise exception 'القيد غير متوازن'; end if;
  insert into public.journal_entries(entry_date,description,source_type,source_id,created_by) values(coalesce(p_entry_date,current_date),p_description,p_source_type,p_source_id,p_created_by) on conflict do nothing returning id into e_id;
  if e_id is null then select id into e_id from public.journal_entries where source_type=p_source_type and source_id=p_source_id limit 1; return e_id; end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    account:=public.account_id(line->>'account_code');
    if account is null then raise exception 'الحساب المحاسبي غير موجود: %',line->>'account_code'; end if;
    insert into public.journal_lines(entry_id,account_id,description,debit,credit) values(e_id,account,line->>'description',greatest(coalesce((line->>'debit')::numeric,0),0),greatest(coalesce((line->>'credit')::numeric,0),0));
  end loop;
  return e_id;
end; $$;

create or replace function public.post_sale_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare cash_total numeric:=0; bank_total numeric:=0; ar_total numeric:=0; revenue numeric:=0; vat numeric:=0; cogs numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(case when payment_method in('cash','partial_cash') then amount else 0 end),0),coalesce(sum(case when payment_method in('bank','partial_bank') then amount else 0 end),0) into cash_total,bank_total from public.sale_payments where sale_id=new.id;
    revenue:=greatest(coalesce(new.subtotal,0)-coalesce(new.discount_amount,0)+coalesce(new.crafting_fee,0),0); vat:=greatest(coalesce(new.vat_amount,0),0); ar_total:=greatest(coalesce(new.total,0)-cash_total-bank_total,0);
    select coalesce(sum(quantity*cost_price),0) into cogs from public.sale_items where sale_id=new.id;
    if cash_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1000','debit',cash_total,'credit',0,'description','تحصيل مبيعات نقدية')); end if;
    if bank_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1010','debit',bank_total,'credit',0,'description','تحصيل مبيعات بنكية')); end if;
    if ar_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1100','debit',ar_total,'credit',0,'description','ذمم العملاء')); end if;
    if revenue>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','4000','debit',0,'credit',revenue,'description','إيراد المبيعات')); end if;
    if vat>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2200','debit',0,'credit',vat,'description','ضريبة مخرجات')); end if;
    if cogs>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','5000','debit',cogs,'credit',0,'description','تكلفة البضاعة المباعة'),jsonb_build_object('account_code','1200','debit',0,'credit',cogs,'description','خروج تكلفة من المخزون')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('sale',new.id,new.sold_at::date,'قيد فاتورة بيع '||new.invoice_number,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_sale_payment_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare s public.sales; lines jsonb:='[]'::jsonb; code text;
begin
  select * into s from public.sales where id=new.sale_id;
  if s.status='approved' and new.amount>0 then
    code:=case when new.payment_method='cash' then '1000' else '1010' end;
    lines:=jsonb_build_array(jsonb_build_object('account_code',code,'debit',new.amount,'credit',0,'description','تحصيل دفعة لاحقة'),jsonb_build_object('account_code','1100','debit',0,'credit',new.amount,'description','تخفيض ذمم العميل'));
    perform public.post_journal('sale_payment',new.id,new.paid_at::date,'دفعة لاحقة لفاتورة بيع',new.created_by,lines);
  end if; return new;
end; $$;

create or replace function public.post_purchase_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare cash_total numeric:=0; bank_total numeric:=0; payable numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    cash_total:=case when new.payment_method='cash' then greatest(coalesce(new.paid_amount,0),0) else 0 end; bank_total:=case when new.payment_method='bank' then greatest(coalesce(new.paid_amount,0),0) else 0 end; payable:=greatest(coalesce(new.total,0)-cash_total-bank_total,0);
    if new.total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1200','debit',new.total,'credit',0,'description','إضافة مخزون من الشراء')); end if;
    if cash_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1000','debit',0,'credit',cash_total,'description','سداد شراء نقدي')); end if;
    if bank_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1010','debit',0,'credit',bank_total,'description','سداد شراء بنكي')); end if;
    if payable>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2000','debit',0,'credit',payable,'description','رصيد مستحق للمورد')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('purchase',new.id,new.purchase_at::date,'قيد شراء '||new.purchase_number,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_expense_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare code text; lines jsonb; begin
  if new.status='approved' and (old.status is distinct from new.status) and new.amount>0 then
    code:=case when new.payment_method='cash' then '1000' else '1010' end;
    lines:=jsonb_build_array(jsonb_build_object('account_code','6000','debit',new.amount,'credit',0,'description',coalesce(new.category,'مصروف تشغيلي')),jsonb_build_object('account_code',code,'debit',0,'credit',new.amount,'description','دفع مصروف'));
    perform public.post_journal('expense',new.id,new.expense_at::date,'قيد مصروف '||new.expense_number,new.created_by,lines);
  end if; return new;
end; $$;

create or replace function public.post_advance_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare code text; lines jsonb; begin
  if new.amount>0 then
    code:=case when new.payment_method='cash' then '1000' else '1010' end;
    lines:=jsonb_build_array(jsonb_build_object('account_code','1300','debit',new.amount,'credit',0,'description','سلفة على العامل'),jsonb_build_object('account_code',code,'debit',0,'credit',new.amount,'description','صرف السلفة'));
    perform public.post_journal('employee_advance',new.id,new.advance_date::date,'قيد سلفة عامل',new.created_by,lines);
  end if; return new;
end; $$;

create or replace function public.post_payroll_accrual_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare gross numeric:=0; advance numeric:=0; payable numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(base_amount+incentives-deductions),0),coalesce(sum(advance_deduction),0) into gross,advance from public.payroll_records where period_id=new.id; payable:=greatest(gross-advance,0);
    if gross>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6100','debit',gross,'credit',0,'description','استحقاق رواتب الفترة')); end if;
    if payable>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2100','debit',0,'credit',payable,'description','رواتب مستحقة')); end if;
    if advance>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1300','debit',0,'credit',advance,'description','تسوية سلف العاملين')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('payroll_period',new.id,new.to_date,'استحقاق مرتبات '||new.period_name,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_payroll_payment_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare code text; lines jsonb; begin
  if new.payment_status='paid' and (old.payment_status is distinct from new.payment_status) and new.paid_amount>0 then
    code:=case when exists(select 1 from public.cash_transactions where related_type='payroll' and related_id=new.id) then '1000' else '1010' end;
    lines:=jsonb_build_array(jsonb_build_object('account_code','2100','debit',new.paid_amount,'credit',0,'description','سداد راتب مستحق'),jsonb_build_object('account_code',code,'debit',0,'credit',new.paid_amount,'description','دفع الراتب'));
    perform public.post_journal('payroll_payment',new.id,coalesce(new.paid_at::date,current_date),'دفع راتب',null,lines);
  end if; return new;
end; $$;

create or replace function public.post_transfer_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare debit_code text; credit_code text; lines jsonb;
begin
  debit_code:=case when new.to_type='cash' then '1000' else '1010' end; credit_code:=case when new.from_type='cash' then '1000' else '1010' end;
  lines:=jsonb_build_array(jsonb_build_object('account_code',debit_code,'debit',new.amount,'credit',0,'description','الحساب المستلم'),jsonb_build_object('account_code',credit_code,'debit',0,'credit',new.amount,'description','الحساب المحول منه'));
  perform public.post_journal('finance_transfer',new.id,new.created_at::date,'تحويل داخلي '||new.transfer_number,new.created_by,lines); return new;
end; $$;

create or replace function public.post_cash_count_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare lines jsonb; begin
  if new.variance>0 then lines:=jsonb_build_array(jsonb_build_object('account_code','1000','debit',new.variance,'credit',0,'description','زيادة جرد الخزنة'),jsonb_build_object('account_code','4100','debit',0,'credit',new.variance,'description','فرق جرد موجب'));
  elsif new.variance<0 then lines:=jsonb_build_array(jsonb_build_object('account_code','6300','debit',abs(new.variance),'credit',0,'description','فرق جرد سالب'),jsonb_build_object('account_code','1000','debit',0,'credit',abs(new.variance),'description','نقص الخزنة')); else return new; end if;
  perform public.post_journal('cash_count',new.id,new.created_at::date,'تسوية جرد خزنة',new.created_by,lines); return new;
end; $$;

create or replace function public.post_return_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare cash_total numeric:=0; bank_total numeric:=0; ar_total numeric:=0; net_return numeric:=0; vat numeric:=0; good_cost numeric:=0; damaged_cost numeric:=0; inspection_cost numeric:=0; lines jsonb:='[]'::jsonb; r record;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(case when sp.cash_register_id is not null then rr.amount else 0 end),0),coalesce(sum(case when sp.bank_id is not null then rr.amount else 0 end),0) into cash_total,bank_total from public.return_refunds rr join public.sale_payments sp on sp.id=rr.sale_payment_id where rr.return_id=new.id;
    net_return:=greatest(coalesce(new.total,0)-coalesce(new.vat_amount,0),0); vat:=greatest(coalesce(new.vat_amount,0),0); ar_total:=greatest(coalesce(new.total,0)-cash_total-bank_total,0);
    select coalesce(sum(ri.good_quantity*si.cost_price),0),coalesce(sum(ri.damaged_quantity*si.cost_price),0),coalesce(sum(ri.inspection_quantity*si.cost_price),0) into good_cost,damaged_cost,inspection_cost from public.return_items ri join public.sale_items si on si.id=ri.sale_item_id where ri.return_id=new.id;
    if net_return>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','4000','debit',net_return,'credit',0,'description','عكس إيراد مرتجع')); end if;
    if vat>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2200','debit',vat,'credit',0,'description','عكس ضريبة مبيعات')); end if;
    if cash_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1000','debit',0,'credit',cash_total,'description','رد نقدي')); end if;
    if bank_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1010','debit',0,'credit',bank_total,'description','رد بنكي')); end if;
    if ar_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1100','debit',0,'credit',ar_total,'description','عكس ذمة العميل')); end if;
    if good_cost+inspection_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1200','debit',good_cost+inspection_cost,'credit',0,'description','عودة مخزون صالح أو فحص')); end if;
    if damaged_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6300','debit',damaged_cost,'credit',0,'description','تكلفة تالف مرتجع')); end if;
    if good_cost+damaged_cost+inspection_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','5000','debit',0,'credit',good_cost+damaged_cost+inspection_cost,'description','عكس تكلفة البضاعة')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('return',new.id,new.return_at::date,'قيد مرتجع '||new.return_number,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_production_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare material_cost numeric:=0; lines jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(quantity*cost_price),0) into material_cost from public.production_materials where production_id=new.id;
    if material_cost>0 then
      lines:=jsonb_build_array(jsonb_build_object('account_code','1220','debit',material_cost,'credit',0,'description','إضافة منتج تام من الإنتاج'),jsonb_build_object('account_code','1210','debit',0,'credit',material_cost,'description','استهلاك مواد خام'));
      perform public.post_journal('production',new.id,coalesce(new.end_at::date,new.created_at::date),'قيد إنتاج '||new.production_number,new.created_by,lines);
    end if;
  end if; return new;
end; $$;

create or replace function public.post_opening_account_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare code text; lines jsonb; begin
  if new.opening_balance>0 then code:=case when tg_table_name='cash_registers' then '1000' else '1010' end; lines:=jsonb_build_array(jsonb_build_object('account_code',code,'debit',new.opening_balance,'credit',0,'description','رصيد افتتاحي'),jsonb_build_object('account_code','3000','debit',0,'credit',new.opening_balance,'description','رأس المال والرصيد الافتتاحي')); perform public.post_journal(case when tg_table_name='cash_registers' then 'cash_register' else 'bank' end,new.id,current_date,'رصيد افتتاحي',new.responsible_id,lines); end if; return new; end; $$;

drop trigger if exists journal_sales_approved on public.sales;
create trigger journal_sales_approved after update of status on public.sales for each row execute function public.post_sale_journal();
drop trigger if exists journal_sale_payments on public.sale_payments;
create trigger journal_sale_payments after insert on public.sale_payments for each row execute function public.post_sale_payment_journal();
drop trigger if exists journal_purchases_approved on public.purchases;
create trigger journal_purchases_approved after update of status on public.purchases for each row execute function public.post_purchase_journal();
drop trigger if exists journal_expenses_approved on public.expenses;
create trigger journal_expenses_approved after update of status on public.expenses for each row execute function public.post_expense_journal();
drop trigger if exists journal_advances on public.employee_advances;
create trigger journal_advances after insert on public.employee_advances for each row execute function public.post_advance_journal();
drop trigger if exists journal_payroll_approved on public.payroll_periods;
create trigger journal_payroll_approved after update of status on public.payroll_periods for each row execute function public.post_payroll_accrual_journal();
drop trigger if exists journal_payroll_paid on public.payroll_records;
create trigger journal_payroll_paid after update of payment_status on public.payroll_records for each row execute function public.post_payroll_payment_journal();
drop trigger if exists journal_transfers on public.finance_transfers;
create trigger journal_transfers after insert on public.finance_transfers for each row execute function public.post_transfer_journal();
drop trigger if exists journal_cash_counts on public.cash_counts;
create trigger journal_cash_counts after insert on public.cash_counts for each row execute function public.post_cash_count_journal();
drop trigger if exists journal_returns_approved on public.returns;
create trigger journal_returns_approved after update of status on public.returns for each row execute function public.post_return_journal();
drop trigger if exists journal_production_approved on public.production_orders;
create trigger journal_production_approved after update of status on public.production_orders for each row execute function public.post_production_journal();
drop trigger if exists journal_cash_opening on public.cash_registers;
create trigger journal_cash_opening after insert on public.cash_registers for each row execute function public.post_opening_account_journal();
drop trigger if exists journal_bank_opening on public.banks;
create trigger journal_bank_opening after insert on public.banks for each row execute function public.post_opening_account_journal();

create or replace function public.add_bank_statement_line(p_bank_id uuid,p_statement_date date,p_reference text,p_description text,p_amount numeric,p_direction text)
returns public.bank_statement_lines language plpgsql security definer set search_path=public as $$declare s public.bank_statement_lines;
begin
  if auth.uid() is null or not public.current_user_has_permission('treasury.reconcile') then raise exception 'غير مصرح بالتسوية البنكية'; end if;
  if p_bank_id is null or p_amount<=0 or p_direction not in('in','out') then raise exception 'بيانات كشف البنك غير صحيحة'; end if;
  insert into public.bank_statement_lines(bank_id,statement_date,reference,description,amount,direction,created_by) values(p_bank_id,coalesce(p_statement_date,current_date),p_reference,p_description,p_amount,p_direction,auth.uid()) returning * into s; return s;
end; $$;

create or replace function public.reconcile_bank_line(p_statement_id uuid,p_bank_transaction_id uuid)
returns public.bank_statement_lines language plpgsql security definer set search_path=public as $$declare s public.bank_statement_lines; t public.bank_transactions;
begin
  if auth.uid() is null or not public.current_user_has_permission('treasury.reconcile') then raise exception 'غير مصرح بالتسوية البنكية'; end if;
  select * into s from public.bank_statement_lines where id=p_statement_id for update; if s.id is null then raise exception 'سطر كشف البنك غير موجود'; end if;
  if p_bank_transaction_id is null then update public.bank_statement_lines set bank_transaction_id=null,reconciled=false,reconciled_at=null,reconciled_by=null where id=s.id returning * into s; return s; end if;
  select * into t from public.bank_transactions where id=p_bank_transaction_id; if t.id is null or t.bank_id<>s.bank_id then raise exception 'الحركة البنكية لا تخص هذا الحساب'; end if;
  if t.amount<>s.amount or t.direction<>s.direction then raise exception 'المبلغ أو اتجاه الحركة لا يطابق كشف البنك'; end if;
  update public.bank_statement_lines set bank_transaction_id=t.id,reconciled=true,reconciled_at=now(),reconciled_by=auth.uid() where id=s.id returning * into s; return s;
end; $$;

grant select on public.chart_accounts,public.journal_entries,public.journal_lines,public.bank_statement_lines to authenticated;
grant execute on function public.add_bank_statement_line(uuid,date,text,text,numeric,text) to authenticated;
grant execute on function public.reconcile_bank_line(uuid,uuid) to authenticated;
revoke all on function public.post_journal(text,uuid,date,text,uuid,jsonb) from public;
revoke all on function public.account_id(text) from public;
revoke all on function public.add_bank_statement_line(uuid,date,text,text,numeric,text) from public;
revoke all on function public.reconcile_bank_line(uuid,uuid) from public;

alter table public.chart_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.bank_statement_lines enable row level security;
drop policy if exists chart_accounts_view on public.chart_accounts;
create policy chart_accounts_view on public.chart_accounts for select using(public.current_user_is_manager() or public.current_user_has_permission('journal.view') or public.current_user_has_permission('reports.financial'));
drop policy if exists journal_entries_view on public.journal_entries;
create policy journal_entries_view on public.journal_entries for select using(public.current_user_is_manager() or public.current_user_has_permission('journal.view') or public.current_user_has_permission('reports.financial'));
drop policy if exists journal_lines_view on public.journal_lines;
create policy journal_lines_view on public.journal_lines for select using(exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and (public.current_user_is_manager() or public.current_user_has_permission('journal.view') or public.current_user_has_permission('reports.financial'))));
drop policy if exists bank_statement_view on public.bank_statement_lines;
create policy bank_statement_view on public.bank_statement_lines for select using(public.current_user_is_manager() or public.current_user_has_permission('treasury.reconcile'));

-- تحديث إعادة الضبط لتشمل اليومية وكشوف البنوك مع الحفاظ على الحسابات والمستخدمين.
create or replace function public.reset_factory_data(p_confirmation text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.current_user_is_manager() then raise exception 'غير مصرح بإعادة ضبط بيانات المصنع'; end if;
  if btrim(coalesce(p_confirmation,'')) <> 'إعادة ضبط المصنع' then raise exception 'عبارة التأكيد غير صحيحة'; end if;
  truncate table public.journal_lines,public.journal_entries,public.bank_statement_lines,public.activity_logs,public.return_refunds,public.return_items,public.returns,public.sale_payments,public.sale_items,public.sales,public.supplier_payments,public.purchase_items,public.purchases,public.raw_materials,public.suppliers,public.production_outputs,public.production_materials,public.production_orders,public.stock_movement_lines,public.stock_movements,public.damaged_goods,public.cash_transactions,public.bank_transactions,public.finance_transfers,public.cash_counts,public.expenses,public.expense_categories,public.payroll_records,public.payroll_periods,public.employee_incentives,public.employee_advances,public.attendance_corrections,public.attendance_records,public.employee_history,public.employees,public.departments,public.job_titles,public.shifts,public.customers,public.warehouses,public.products,public.product_categories,public.units,public.cash_registers,public.banks restart identity;
  alter sequence if exists public.product_seq restart with 1; alter sequence if exists public.employee_seq restart with 1; alter sequence if exists public.warehouse_seq restart with 1; alter sequence if exists public.movement_seq restart with 1; alter sequence if exists public.supplier_seq restart with 1; alter sequence if exists public.raw_seq restart with 1; alter sequence if exists public.purchase_seq restart with 1; alter sequence if exists public.invoice_seq restart with 1; alter sequence if exists public.return_seq restart with 1; alter sequence if exists public.damage_seq restart with 1; alter sequence if exists public.cash_seq restart with 1; alter sequence if exists public.bank_seq restart with 1; alter sequence if exists public.cash_tx_seq restart with 1; alter sequence if exists public.bank_tx_seq restart with 1; alter sequence if exists public.expense_seq restart with 1; alter sequence if exists public.journal_seq restart with 1;
  insert into public.activity_logs(actor_id,action,entity_type,reason,severity) values(auth.uid(),'RESET','factory','إعادة ضبط بيانات التشغيل مع الحفاظ على المستخدمين والحسابات المحاسبية والصلاحيات','critical');
end; $$;
revoke all on function public.reset_factory_data(text) from public;
grant execute on function public.reset_factory_data(text) to authenticated;
