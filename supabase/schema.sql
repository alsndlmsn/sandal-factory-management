-- Sandal Plastic Containers Factory
-- تشغيل هذا الملف مرة واحدة في Supabase SQL Editor.
-- لا يحتوي هذا الملف على أي مفاتيح سرية.

create extension if not exists pgcrypto;
create schema if not exists private;

create type public.app_role as enum ('manager', 'sales', 'warehouse', 'cashier', 'payroll');
create type public.document_status as enum ('draft', 'approved', 'cancelled');
create type public.item_type as enum ('raw_material', 'finished_product');
create type public.account_type as enum ('cash', 'bank');
create type public.payment_method as enum ('cash', 'bank');
create type public.wage_type as enum ('monthly', 'daily', 'hourly');
create type public.worker_status as enum ('active', 'inactive');

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text,
  email text,
  role public.app_role not null default 'sales',
  manage_prices boolean not null default false,
  is_enabled boolean not null default true,
  must_change_password boolean not null default false,
  password_reset_at timestamptz,
  last_sign_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code in ('kilogram','piece','roll','bundle','meter')),
  name_ar text not null,
  created_at timestamptz not null default now()
);

insert into public.units (code, name_ar) values
  ('kilogram','كيلوجرام'), ('piece','قطعة'), ('roll','لفة'), ('bundle','ربطة'), ('meter','متر')
on conflict (code) do nothing;

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text unique,
  address text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  item_type public.item_type not null,
  code text unique,
  category text,
  size text,
  volume text,
  color text,
  thickness text,
  base_unit text not null references public.units(code),
  purchase_price numeric(18,2) not null default 0 check (purchase_price >= 0),
  sale_price numeric(18,2) not null default 0 check (sale_price >= 0),
  minimum_stock numeric(18,3) not null default 0 check (minimum_stock >= 0),
  notes text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.item_unit_conversions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  from_unit text not null references public.units(code),
  to_unit text not null references public.units(code),
  conversion_factor numeric(18,6) not null check (conversion_factor > 0),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (item_id, from_unit, to_unit)
);

create table if not exists public.item_price_history (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  price_type text not null check (price_type in ('purchase','sale')),
  previous_price numeric(18,2) not null check (previous_price >= 0),
  new_price numeric(18,2) not null check (new_price >= 0),
  reason text not null check (length(btrim(reason)) >= 3),
  actor_id uuid not null references public.profiles(id),
  actor_display_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  account_type public.account_type not null,
  bank_name text,
  account_number_masked text,
  opening_balance numeric(18,2) not null default 0 check (opening_balance >= 0),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (account_type = 'cash' or length(btrim(coalesce(bank_name,''))) > 0)
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  customer_id uuid references public.customers(id) on delete restrict,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  payment_method public.payment_method not null,
  bank_reference text,
  subtotal numeric(18,2) not null default 0 check (subtotal >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  total numeric(18,2) not null default 0 check (total >= 0),
  notes text,
  status public.document_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (payment_method <> 'bank' or length(btrim(coalesce(bank_reference,''))) > 0)
);

create table if not exists public.sale_lines (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  item_id uuid not null references public.items(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0),
  unit text not null references public.units(code),
  unit_price_snapshot numeric(18,2) not null check (unit_price_snapshot >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  line_total numeric(18,2) generated always as ((quantity * unit_price_snapshot) - discount) stored,
  created_at timestamptz not null default now(),
  check ((quantity * unit_price_snapshot) >= discount)
);

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  transaction_type text not null check (transaction_type in ('inbound','outbound','adjustment')),
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  item_id uuid references public.items(id) on delete restrict,
  sale_id uuid references public.sales(id) on delete restrict,
  quantity numeric(18,3) check (quantity is null or quantity >= 0),
  unit text references public.units(code),
  movement_sign smallint not null default 1 check (movement_sign in (-1,1)),
  source_document_reference text unique,
  reason text,
  allow_negative_exception boolean not null default false,
  status public.document_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((transaction_type = 'adjustment') or (sale_id is not null and warehouse_id is not null) or (item_id is not null and warehouse_id is not null and quantity is not null and quantity > 0)),
  check (transaction_type <> 'outbound' or movement_sign = -1)
);

create table if not exists public.inventory_transaction_lines (
  id uuid primary key default gen_random_uuid(),
  inventory_transaction_id uuid not null references public.inventory_transactions(id) on delete restrict,
  item_id uuid not null references public.items(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0),
  unit text not null references public.units(code),
  created_at timestamptz not null default now()
);

create table if not exists public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('cash_in','cash_out','bank_in','bank_out')),
  payment_method public.payment_method not null,
  amount numeric(18,2) not null check (amount > 0),
  bank_reference text,
  source_document_reference text unique,
  reason text,
  allow_negative_exception boolean not null default false,
  status public.document_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (transaction_type not in ('bank_in','bank_out') or length(btrim(coalesce(bank_reference,''))) > 0),
  check (transaction_type in ('cash_in','cash_out') or payment_method = 'bank')
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  category text not null,
  beneficiary text not null,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  payment_method public.payment_method not null,
  bank_reference text,
  amount numeric(18,2) not null check (amount > 0),
  description text,
  status public.document_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (payment_method <> 'bank' or length(btrim(coalesce(bank_reference,''))) > 0)
);

create table if not exists public.workers (
  id uuid primary key default gen_random_uuid(),
  employee_number text not null unique,
  full_name text not null,
  department text,
  job_title text,
  wage_type public.wage_type not null,
  base_wage numeric(18,2) not null default 0 check (base_wage >= 0),
  phone text,
  status public.worker_status not null default 'active',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.worker_advances (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.workers(id) on delete restrict,
  document_number text not null unique,
  amount numeric(18,2) not null check (amount > 0),
  advance_date date not null,
  deduction_amount numeric(18,2) not null default 0 check (deduction_amount >= 0 and deduction_amount <= amount),
  status public.document_status not null default 'draft',
  reason text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  period_start date not null,
  period_end date not null,
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  status public.document_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_start, period_end),
  check (period_end >= period_start)
);

create table if not exists public.payroll_entries (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs(id) on delete restrict,
  worker_id uuid not null references public.workers(id) on delete restrict,
  base_wage numeric(18,2) not null default 0 check (base_wage >= 0),
  allowances numeric(18,2) not null default 0 check (allowances >= 0),
  overtime numeric(18,2) not null default 0 check (overtime >= 0),
  bonuses numeric(18,2) not null default 0 check (bonuses >= 0),
  deductions numeric(18,2) not null default 0 check (deductions >= 0),
  advance_deductions numeric(18,2) not null default 0 check (advance_deductions >= 0),
  penalties numeric(18,2) not null default 0 check (penalties >= 0),
  net_amount numeric(18,2) generated always as (base_wage + allowances + overtime + bonuses - deductions - advance_deductions - penalties) stored,
  paid_amount numeric(18,2) not null default 0 check (paid_amount >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','partially_paid','paid')),
  recipient_name text,
  receipt_timestamp timestamptz,
  created_at timestamptz not null default now(),
  unique (payroll_run_id, worker_id),
  check ((base_wage + allowances + overtime + bonuses) >= (deductions + advance_deductions + penalties)),
  check (paid_amount <= net_amount)
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id),
  actor_display_name text not null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  reason text,
  severity text not null default 'normal' check (severity in ('normal','high','critical')),
  local_display_time text,
  created_at timestamptz not null default now()
);

create index if not exists idx_profiles_role_enabled on public.profiles(role, is_enabled);
create index if not exists idx_items_active_category on public.items(is_active, category);
create index if not exists idx_inventory_status_date on public.inventory_transactions(status, created_at);
create index if not exists idx_inventory_warehouse_item on public.inventory_transactions(warehouse_id, item_id, status);
create index if not exists idx_inventory_lines_item on public.inventory_transaction_lines(item_id, inventory_transaction_id);
create index if not exists idx_sales_status_date on public.sales(status, created_at);
create index if not exists idx_financial_status_account on public.financial_transactions(status, financial_account_id, created_at);
create index if not exists idx_expenses_status_date on public.expenses(status, created_at);
create index if not exists idx_workers_department_status on public.workers(department, status);
create index if not exists idx_payroll_period on public.payroll_runs(period_start, period_end, status);
create index if not exists idx_audit_date_entity on public.audit_logs(created_at, entity_type);
create unique index if not exists uq_bank_reference_per_account on public.financial_transactions(financial_account_id, bank_reference) where bank_reference is not null and length(btrim(bank_reference)) > 0;

create or replace function private.current_app_role()
returns text language sql stable security definer set search_path = public, private, pg_temp as $$
  select role::text from public.profiles where id = auth.uid() and is_enabled = true and must_change_password = false limit 1;
$$;

create or replace function private.has_permission(permission_name text)
returns boolean language plpgsql stable security definer set search_path = public, private, pg_temp as $$
declare r text;
begin
  select role::text into r from public.profiles where id = auth.uid() and is_enabled = true and must_change_password = false;
  if r is null then return false; end if;
  if r = 'manager' then return true; end if;
  if permission_name = 'sales' and r = 'sales' then return true; end if;
  if permission_name = 'warehouse' and r = 'warehouse' then return true; end if;
  if permission_name = 'finance' and r = 'cashier' then return true; end if;
  if permission_name = 'payroll' and r = 'payroll' then return true; end if;
  if permission_name = 'reports' and r in ('sales','warehouse','cashier','payroll') then return true; end if;
  if permission_name = 'manage_prices' then return exists (select 1 from public.profiles p where p.id = auth.uid() and p.manage_prices);
  return false;
end;
$$;

create or replace function private.is_manager()
returns boolean language sql stable security definer set search_path = public, private, pg_temp as $$ select private.current_app_role() = 'manager'; $$;

create or replace function private.audit_event(p_action text, p_entity_type text, p_entity_id uuid, p_before jsonb, p_after jsonb, p_reason text default null, p_severity text default 'normal')
returns void language plpgsql security definer set search_path = public, private, pg_temp as $$
declare display_name text;
begin
  if auth.uid() is null then raise exception 'جلسة غير صالحة'; end if;
  select coalesce(full_name, email, 'مستخدم') into display_name from public.profiles where id = auth.uid();
  insert into public.audit_logs(actor_id, actor_display_name, action, entity_type, entity_id, before_data, after_data, reason, severity, local_display_time)
  values (auth.uid(), coalesce(display_name,'مستخدم'), p_action, p_entity_type, p_entity_id, p_before, p_after, p_reason, p_severity, to_char(now() at time zone 'Africa/Khartoum','YYYY-MM-DD HH24:MI:SS'));
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles(id, full_name, email) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email) on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.dashboard_summary()
returns json language plpgsql stable security definer set search_path = public, private, pg_temp as $$
declare result json;
begin
  if auth.uid() is null or private.current_app_role() is null then raise exception 'غير مصرح'; end if;
  select json_build_object(
    'approved_sales', coalesce((select sum(total) from public.sales where status='approved'),0),
    'registered_items', (select count(*) from public.items where is_active=true),
    'low_stock_count', (select count(*) from public.v_low_stock),
    'cash_balance', coalesce((select sum(balance) from public.v_financial_balances where account_type='cash'),0),
    'approved_expenses', coalesce((select sum(amount) from public.expenses where status='approved'),0),
    'approved_payroll_total', coalesce((select sum(total_amount) from public.payroll_runs where status='approved'),0)
  ) into result;
  return result;
end;
$$;

create or replace view public.v_stock_balances as
with movements as (
  select t.warehouse_id, t.item_id,
    case when t.transaction_type='inbound' then t.quantity when t.transaction_type='outbound' then -t.quantity when t.transaction_type='adjustment' then t.quantity*t.movement_sign else 0 end as quantity
  from public.inventory_transactions t
  where t.status='approved' and t.item_id is not null
  union all
  select t.warehouse_id, l.item_id,
    case when t.transaction_type='inbound' then l.quantity when t.transaction_type='outbound' then -l.quantity when t.transaction_type='adjustment' then l.quantity*t.movement_sign else 0 end as quantity
  from public.inventory_transactions t join public.inventory_transaction_lines l on l.inventory_transaction_id=t.id
  where t.status='approved' and t.item_id is null
)
select w.id as warehouse_id, w.name as warehouse_name, i.id as item_id, i.name as item_name, i.minimum_stock,
  coalesce(sum(m.quantity),0)::numeric(18,3) as balance
from public.warehouses w cross join public.items i left join movements m on m.warehouse_id=w.id and m.item_id=i.id
where w.is_active=true and i.is_active=true group by w.id,w.name,i.id,i.name,i.minimum_stock;

create or replace view public.v_low_stock as select * from public.v_stock_balances where balance < minimum_stock;

create or replace view public.v_financial_balances as
select a.id as financial_account_id, a.name, a.account_type, a.bank_name, a.opening_balance + coalesce(sum(case when t.transaction_type in ('cash_in','bank_in') then t.amount when t.transaction_type in ('cash_out','bank_out') then -t.amount else 0 end),0) as balance
from public.financial_accounts a left join public.financial_transactions t on t.financial_account_id=a.id and t.status='approved'
where a.is_active=true group by a.id,a.name,a.account_type,a.bank_name,a.opening_balance;

create or replace function public.approve_inventory_transaction(p_transaction_id uuid, p_exception_reason text default null)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare doc public.inventory_transactions; current_balance numeric; before_row jsonb; after_row jsonb; line_count integer;
begin
  if not (private.has_permission('warehouse') or private.is_manager()) then raise exception 'ليست لديك صلاحية اعتماد حركة المخزون'; end if;
  select * into doc from public.inventory_transactions where id=p_transaction_id for update;
  if not found then raise exception 'حركة المخزون غير موجودة'; end if;
  if doc.status <> 'draft' then raise exception 'لا يمكن اعتماد حركة ليست مسودة'; end if;
  if doc.quantity is not null and doc.quantity <= 0 then raise exception 'الكمية يجب أن تكون أكبر من صفر'; end if;
  if doc.transaction_type='outbound' then
    select coalesce(sum(case when t.transaction_type='inbound' then t.quantity when t.transaction_type='outbound' then -t.quantity when t.transaction_type='adjustment' then t.quantity*t.movement_sign else 0 end),0) into current_balance from public.inventory_transactions t where t.warehouse_id=doc.warehouse_id and t.item_id=doc.item_id and t.status='approved';
    if current_balance < doc.quantity and not (private.is_manager() and length(btrim(coalesce(p_exception_reason,''))) >= 3) then raise exception 'الرصيد الحالي لا يسمح بالمنصرف'; end if;
  end if;
  before_row := to_jsonb(doc);
  update public.inventory_transactions set status='approved', approved_by=auth.uid(), approved_at=now(), allow_negative_exception=(private.is_manager() and p_exception_reason is not null), reason=case when p_exception_reason is not null then concat_ws(' — ', reason, p_exception_reason) else reason end, updated_at=now() where id=p_transaction_id;
  select to_jsonb(t) into after_row from public.inventory_transactions t where t.id=p_transaction_id;
  perform private.audit_event('approval','inventory_transaction',p_transaction_id,before_row,after_row,p_exception_reason,case when p_exception_reason is not null then 'high' else 'normal' end);
  return p_transaction_id;
end;
$$;

create or replace function public.approve_financial_transaction(p_transaction_id uuid, p_exception_reason text default null)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare doc public.financial_transactions; account public.financial_accounts; current_balance numeric; before_row jsonb; after_row jsonb;
begin
  if not (private.has_permission('finance') or private.is_manager()) then raise exception 'ليست لديك صلاحية اعتماد الحركة المالية'; end if;
  select * into doc from public.financial_transactions where id=p_transaction_id for update;
  if not found or doc.status <> 'draft' then raise exception 'الحركة غير موجودة أو ليست مسودة'; end if;
  select * into account from public.financial_accounts where id=doc.financial_account_id for update;
  if doc.transaction_type in ('bank_in','bank_out') and account.account_type <> 'bank' then raise exception 'الحركة البنكية يجب أن ترتبط بحساب بنك'; end if;
  if doc.transaction_type in ('cash_in','cash_out') and account.account_type <> 'cash' then raise exception 'الحركة النقدية يجب أن ترتبط بحساب نقدية'; end if;
  if doc.transaction_type in ('cash_out','bank_out') then
    select account.opening_balance + coalesce(sum(case when t.transaction_type in ('cash_in','bank_in') then t.amount when t.transaction_type in ('cash_out','bank_out') then -t.amount else 0 end),0) into current_balance from public.financial_transactions t where t.financial_account_id=account.id and t.status='approved';
    if current_balance < doc.amount and not (private.is_manager() and length(btrim(coalesce(p_exception_reason,''))) >= 3) then raise exception 'الرصيد لا يسمح بالدفع'; end if;
  end if;
  before_row := to_jsonb(doc);
  update public.financial_transactions set status='approved', approved_by=auth.uid(), approved_at=now(), allow_negative_exception=(private.is_manager() and p_exception_reason is not null), reason=case when p_exception_reason is not null then concat_ws(' — ', reason, p_exception_reason) else reason end, updated_at=now() where id=p_transaction_id;
  select to_jsonb(t) into after_row from public.financial_transactions t where t.id=p_transaction_id;
  perform private.audit_event('approval','financial_transaction',p_transaction_id,before_row,after_row,p_exception_reason,case when p_exception_reason is not null then 'high' else 'normal' end);
  return p_transaction_id;
end;
$$;

create or replace function public.approve_expense(p_expense_id uuid, p_exception_reason text default null)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare e public.expenses; generated_id uuid;
begin
  if not (private.has_permission('finance') or private.is_manager()) then raise exception 'ليست لديك صلاحية اعتماد المصروف'; end if;
  select * into e from public.expenses where id=p_expense_id for update;
  if not found or e.status <> 'draft' then raise exception 'المصروف غير موجود أو ليس مسودة'; end if;
  if not exists (select 1 from public.financial_transactions where source_document_reference='expense:'||e.id) then
    insert into public.financial_transactions(document_number,financial_account_id,transaction_type,payment_method,amount,bank_reference,source_document_reference,reason,status,created_by,approved_by,approved_at)
    values ('EXP-PAY-'||e.document_number,e.financial_account_id,case when e.payment_method='bank' then 'bank_out' else 'cash_out' end,e.payment_method,e.amount,e.bank_reference,'expense:'||e.id,e.description,'approved',e.created_by,auth.uid(),now()) returning id into generated_id;
  end if;
  update public.expenses set status='approved', approved_by=auth.uid(), approved_at=now(), updated_at=now() where id=e.id;
  perform private.audit_event('approval','expense',e.id,to_jsonb(e),(select to_jsonb(x) from public.expenses x where x.id=e.id),p_exception_reason);
  return e.id;
end;
$$;

create or replace function public.approve_sale(p_sale_id uuid)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare s public.sales; a public.financial_accounts; calculated numeric; stock_id uuid; line public.sale_lines; before_row jsonb; current_stock numeric;
begin
  if not (private.has_permission('sales') or private.is_manager()) then raise exception 'ليست لديك صلاحية اعتماد البيع'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if not found or s.status <> 'draft' then raise exception 'الفاتورة غير موجودة أو ليست مسودة'; end if;
  if s.total <= 0 then raise exception 'قيمة البيع يجب أن تكون أكبر من صفر'; end if;
  if s.payment_method='bank' and length(btrim(coalesce(s.bank_reference,'')))=0 then raise exception 'المرجع البنكي إلزامي'; end if;
  if s.financial_account_id is null then raise exception 'الحساب المالي إلزامي'; end if;
  select * into a from public.financial_accounts where id=s.financial_account_id for update;
  if (s.payment_method='cash' and a.account_type<>'cash') or (s.payment_method='bank' and a.account_type<>'bank') then raise exception 'نوع الحساب لا يطابق طريقة الدفع'; end if;
  select coalesce(sum(line_total),0) into calculated from public.sale_lines where sale_id=s.id;
  if calculated <> s.total then raise exception 'إجمالي الفاتورة لا يطابق مجموع البنود'; end if;
  if not exists (select 1 from public.sale_lines where sale_id=s.id) then raise exception 'لا يمكن اعتماد فاتورة بدون بنود'; end if;
  before_row := to_jsonb(s);
  if exists (select 1 from public.inventory_transactions where source_document_reference='sale:'||s.id) then raise exception 'تمت معالجة الفاتورة مسبقًا'; end if;
  perform 1 from public.warehouses where id=s.warehouse_id for update;
  insert into public.inventory_transactions(document_number,transaction_type,warehouse_id,sale_id,source_document_reference,reason,status,created_by,approved_by,approved_at)
  values ('INV-SALE-'||s.document_number,'outbound',s.warehouse_id,s.id,'sale:'||s.id,'منصرف مرتبط بفاتورة بيع','approved',s.created_by,auth.uid(),now()) returning id into stock_id;
  for line in select * from public.sale_lines where sale_id=s.id loop
    select coalesce(v.balance,0) into current_stock from public.v_stock_balances v where v.warehouse_id=s.warehouse_id and v.item_id=line.item_id;
    if current_stock < line.quantity then raise exception 'الرصيد لا يسمح ببيع الصنف'; end if;
    insert into public.inventory_transaction_lines(inventory_transaction_id,item_id,quantity,unit) values (stock_id,line.item_id,line.quantity,line.unit);
  end loop;
  insert into public.financial_transactions(document_number,financial_account_id,transaction_type,payment_method,amount,bank_reference,source_document_reference,reason,status,created_by,approved_by,approved_at)
  values ('SALE-'||s.document_number,s.financial_account_id,case when s.payment_method='bank' then 'bank_in' else 'cash_in' end,s.payment_method,s.total,s.bank_reference,'sale:'||s.id,'تحصيل مرتبط بفاتورة بيع','approved',s.created_by,auth.uid(),now());
  update public.sales set status='approved', approved_by=auth.uid(), approved_at=now(), updated_at=now() where id=s.id;
  perform private.audit_event('approval','sale',s.id,before_row,(select to_jsonb(x) from public.sales x where x.id=s.id),null);
  return s.id;
end;
$$;

create or replace function public.change_item_price(p_item_id uuid, p_price_type text, p_new_price numeric, p_reason text)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare i public.items; previous numeric; before_row jsonb;
begin
  if not private.has_permission('manage_prices') then raise exception 'تغيير الأسعار متاح للمدير أو المفوض فقط'; end if;
  if p_price_type not in ('purchase','sale') or p_new_price is null or p_new_price < 0 or length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'بيانات تغيير السعر غير صحيحة'; end if;
  select * into i from public.items where id=p_item_id for update;
  if not found then raise exception 'الصنف غير موجود'; end if;
  previous := case when p_price_type='purchase' then i.purchase_price else i.sale_price end;
  before_row := to_jsonb(i);
  if p_price_type='purchase' then update public.items set purchase_price=p_new_price, updated_at=now() where id=i.id; else update public.items set sale_price=p_new_price, updated_at=now() where id=i.id; end if;
  insert into public.item_price_history(item_id,price_type,previous_price,new_price,reason,actor_id,actor_display_name) select i.id,p_price_type,previous,p_new_price,p_reason,auth.uid(),coalesce(full_name,email,'مستخدم') from public.profiles where id=auth.uid();
  perform private.audit_event('price_change','item',i.id,before_row,(select to_jsonb(x) from public.items x where x.id=i.id),p_reason,'high');
  return i.id;
end;
$$;

create or replace function public.create_payroll_run(p_document_number text, p_period_start date, p_period_end date, p_entries jsonb)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare run_id uuid; entry jsonb; worker_id uuid; total numeric := 0;
begin
  if not (private.has_permission('payroll') or private.is_manager()) then raise exception 'ليست لديك صلاحية إنشاء كشف الرواتب'; end if;
  if length(btrim(coalesce(p_document_number,''))) < 3 or p_period_end < p_period_start or jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries)=0 then raise exception 'بيانات كشف الرواتب غير صحيحة'; end if;
  insert into public.payroll_runs(document_number,period_start,period_end,created_by) values (p_document_number,p_period_start,p_period_end,auth.uid()) returning id into run_id;
  for entry in select * from jsonb_array_elements(p_entries) loop
    worker_id := (entry->>'worker_id')::uuid;
    if not exists (select 1 from public.workers where id=worker_id and status='active') then raise exception 'العامل غير موجود أو غير نشط'; end if;
    insert into public.payroll_entries(payroll_run_id,worker_id,base_wage,allowances,overtime,bonuses,deductions,advance_deductions,penalties)
    values (run_id,worker_id,coalesce((entry->>'base_wage')::numeric,0),coalesce((entry->>'allowances')::numeric,0),coalesce((entry->>'overtime')::numeric,0),coalesce((entry->>'bonuses')::numeric,0),coalesce((entry->>'deductions')::numeric,0),coalesce((entry->>'advance_deductions')::numeric,0),coalesce((entry->>'penalties')::numeric,0));
  end loop;
  select coalesce(sum(net_amount),0) into total from public.payroll_entries where payroll_run_id=run_id;
  update public.payroll_runs set total_amount=total where id=run_id;
  perform private.audit_event('create','payroll_run',run_id,null,(select to_jsonb(x) from public.payroll_runs x where x.id=run_id),null);
  return run_id;
end;
$$;

create or replace function public.approve_payroll_run(p_payroll_run_id uuid)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare r public.payroll_runs; before_row jsonb;
begin
  if not (private.has_permission('payroll') or private.is_manager()) then raise exception 'ليست لديك صلاحية اعتماد كشف الرواتب'; end if;
  select * into r from public.payroll_runs where id=p_payroll_run_id for update;
  if not found or r.status<>'draft' then raise exception 'الكشف غير موجود أو ليس مسودة'; end if;
  if not exists (select 1 from public.payroll_entries where payroll_run_id=r.id) then raise exception 'الكشف بلا عمال'; end if;
  before_row := to_jsonb(r);
  update public.payroll_runs set status='approved', approved_by=auth.uid(), approved_at=now(), updated_at=now() where id=r.id;
  perform private.audit_event('approval','payroll_run',r.id,before_row,(select to_jsonb(x) from public.payroll_runs x where x.id=r.id),null);
  return r.id;
end;
$$;

create or replace function public.pay_payroll_entry(p_entry_id uuid, p_financial_account_id uuid, p_amount numeric, p_recipient_name text)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare e public.payroll_entries; r public.payroll_runs; a public.financial_accounts; unpaid numeric; txn_id uuid;
begin
  if not (private.has_permission('payroll') or private.is_manager()) then raise exception 'ليست لديك صلاحية دفع الرواتب'; end if;
  select * into e from public.payroll_entries where id=p_entry_id for update;
  if not found then raise exception 'قيد الراتب غير موجود'; end if;
  select * into r from public.payroll_runs where id=e.payroll_run_id;
  if r.status<>'approved' then raise exception 'لا يمكن دفع كشف غير معتمد'; end if;
  unpaid := e.net_amount - e.paid_amount;
  if p_amount is null or p_amount <= 0 or p_amount > unpaid then raise exception 'مبلغ الدفع يتجاوز المستحق غير المدفوع'; end if;
  select * into a from public.financial_accounts where id=p_financial_account_id for update;
  if a.account_type<>'cash' then raise exception 'دفع الرواتب في هذه النسخة يتطلب حساب نقدية'; end if;
  if a.opening_balance + coalesce((select sum(case when transaction_type in ('cash_in','bank_in') then amount when transaction_type in ('cash_out','bank_out') then -amount else 0 end) from public.financial_transactions where financial_account_id=a.id and status='approved'),0) < p_amount then raise exception 'الرصيد النقدي لا يكفي'; end if;
  insert into public.financial_transactions(document_number,financial_account_id,transaction_type,payment_method,amount,source_document_reference,reason,status,created_by,approved_by,approved_at)
  values ('PAYROLL-'||e.id,p_financial_account_id,'cash_out','cash',p_amount,'payroll_entry:'||e.id,'دفع راتب','approved',auth.uid(),auth.uid(),now()) returning id into txn_id;
  update public.payroll_entries set paid_amount=paid_amount+p_amount, payment_status=case when paid_amount+p_amount=net_amount then 'paid' else 'partially_paid' end, recipient_name=p_recipient_name, receipt_timestamp=now() where id=e.id;
  perform private.audit_event('pay','payroll_entry',e.id,null,(select to_jsonb(x) from public.payroll_entries x where x.id=e.id),null);
  return txn_id;
end;
$$;

create or replace function public.cancel_document(p_entity_type text, p_entity_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare before_row jsonb; after_row jsonb;
begin
  if not private.is_manager() or length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'الإلغاء للمدير فقط ويتطلب سببًا واضحًا'; end if;
  if p_entity_type='sale' then select to_jsonb(s) into before_row from public.sales s where id=p_entity_id; update public.sales set status='cancelled',cancelled_by=auth.uid(),cancellation_reason=p_reason,updated_at=now() where id=p_entity_id and status<>'cancelled'; select to_jsonb(s) into after_row from public.sales s where id=p_entity_id;
  elsif p_entity_type='inventory_transaction' then select to_jsonb(t) into before_row from public.inventory_transactions t where id=p_entity_id; update public.inventory_transactions set status='cancelled',cancelled_by=auth.uid(),cancellation_reason=p_reason,updated_at=now() where id=p_entity_id and status<>'cancelled'; select to_jsonb(t) into after_row from public.inventory_transactions t where id=p_entity_id;
  elsif p_entity_type='financial_transaction' then select to_jsonb(t) into before_row from public.financial_transactions t where id=p_entity_id; update public.financial_transactions set status='cancelled',cancelled_by=auth.uid(),cancellation_reason=p_reason,updated_at=now() where id=p_entity_id and status<>'cancelled'; select to_jsonb(t) into after_row from public.financial_transactions t where id=p_entity_id;
  elsif p_entity_type='expense' then select to_jsonb(e) into before_row from public.expenses e where id=p_entity_id; update public.expenses set status='cancelled',cancelled_by=auth.uid(),cancellation_reason=p_reason,updated_at=now() where id=p_entity_id and status<>'cancelled'; select to_jsonb(e) into after_row from public.expenses e where id=p_entity_id;
  elsif p_entity_type='payroll_run' then select to_jsonb(r) into before_row from public.payroll_runs r where id=p_entity_id; update public.payroll_runs set status='cancelled',updated_at=now() where id=p_entity_id and status<>'cancelled'; select to_jsonb(r) into after_row from public.payroll_runs r where id=p_entity_id;
  else raise exception 'نوع المستند غير مسموح'; end if;
  if before_row is null then raise exception 'المستند غير موجود'; end if;
  perform private.audit_event('cancellation',p_entity_type,p_entity_id,before_row,after_row,p_reason,'high');
  return p_entity_id;
end;
$$;

create or replace function public.change_user_role(p_target_user_id uuid, p_new_role public.app_role, p_reason text)
returns uuid language plpgsql security definer set search_path = public, private, pg_temp as $$
declare before_row jsonb; after_row jsonb;
begin
  if not private.is_manager() or p_target_user_id=auth.uid() or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'تغيير الدور متاح للمدير مع سبب، ولا يمكن تغيير دورك'; end if;
  select to_jsonb(p) into before_row from public.profiles p where id=p_target_user_id;
  if before_row is null then raise exception 'المستخدم غير موجود'; end if;
  update public.profiles set role=p_new_role, updated_at=now() where id=p_target_user_id;
  select to_jsonb(p) into after_row from public.profiles p where id=p_target_user_id;
  perform private.audit_event('role_change','profile',p_target_user_id,before_row,after_row,p_reason,'high');
  return p_target_user_id;
end;
$$;

create or replace function public.complete_password_change()
returns boolean language plpgsql security definer set search_path = public, private, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'جلسة غير صالحة'; end if;
  update public.profiles set must_change_password=false, password_reset_at=null, updated_at=now() where id=auth.uid();
  perform private.audit_event('password_change','profile',auth.uid(),null,jsonb_build_object('must_change_password',false),'password changed');
  return true;
end;
$$;

create or replace function public.daily_reconciliation(p_from date, p_to date)
returns table(reconciliation_type text, document_number text, expected_amount numeric, actual_amount numeric, difference numeric)
language plpgsql stable security definer set search_path = public, private, pg_temp as $$
begin
  if not private.is_manager() then raise exception 'تقرير المطابقة للمدير فقط'; end if;
  return query
  select 'مبيعات مقابل تحصيل'::text, s.document_number, s.total, coalesce(ft.amount,0), s.total-coalesce(ft.amount,0)
  from public.sales s left join public.financial_transactions ft on ft.source_document_reference='sale:'||s.id and ft.status='approved'
  where s.status='approved' and s.created_at::date between p_from and p_to and s.total<>coalesce(ft.amount,0)
  union all
  select 'مصروفات مقابل دفع'::text, e.document_number, e.amount, coalesce(ft.amount,0), e.amount-coalesce(ft.amount,0)
  from public.expenses e left join public.financial_transactions ft on ft.source_document_reference='expense:'||e.id and ft.status='approved'
  where e.status='approved' and e.created_at::date between p_from and p_to and e.amount<>coalesce(ft.amount,0)
  union all
  select 'رواتب مقابل دفع'::text, r.document_number, r.total_amount, coalesce(x.paid_amount,0), r.total_amount-coalesce(x.paid_amount,0)
  from public.payroll_runs r left join (select pe.payroll_run_id,sum(pe.paid_amount) paid_amount from public.payroll_entries pe group by pe.payroll_run_id) x on x.payroll_run_id=r.id
  where r.status='approved' and r.created_at::date between p_from and p_to and r.total_amount<>coalesce(x.paid_amount,0);
end;
$$;

-- تفعيل RLS على كل الجداول المكشوفة في public قبل الاعتماد على السياسات.
alter table public.profiles enable row level security;
alter table public.units enable row level security;
alter table public.warehouses enable row level security;
alter table public.items enable row level security;
alter table public.item_unit_conversions enable row level security;
alter table public.item_price_history enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.sales enable row level security;
alter table public.sale_lines enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.inventory_transaction_lines enable row level security;
alter table public.financial_transactions enable row level security;
alter table public.expenses enable row level security;
alter table public.workers enable row level security;
alter table public.worker_advances enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_entries enable row level security;
alter table public.audit_logs enable row level security;

-- المنح: لا يوجد وصول مجهول إلى أي بيانات تشغيلية.
revoke all on public.v_stock_balances, public.v_low_stock, public.v_financial_balances from anon, authenticated;
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on schema public to authenticated;
revoke all on schema private from public, anon, authenticated;

-- سياسات SELECT منفصلة حسب أقل صلاحية.
create policy profiles_select on public.profiles for select to authenticated using (id=auth.uid() or private.is_manager());
create policy units_select on public.units for select to authenticated using (private.has_permission('warehouse') or private.has_permission('sales'));
create policy warehouses_select on public.warehouses for select to authenticated using (private.has_permission('warehouse') or private.has_permission('sales'));
create policy items_select on public.items for select to authenticated using (private.has_permission('warehouse') or private.has_permission('sales'));
create policy item_conversions_select on public.item_unit_conversions for select to authenticated using (private.has_permission('warehouse'));
create policy price_history_select on public.item_price_history for select to authenticated using (private.has_permission('manage_prices'));
create policy customers_select on public.customers for select to authenticated using (private.has_permission('sales') or private.is_manager());
create policy suppliers_select on public.suppliers for select to authenticated using (private.has_permission('warehouse') or private.is_manager());
create policy inventory_select on public.inventory_transactions for select to authenticated using (private.has_permission('warehouse') or private.is_manager());
create policy inventory_lines_select on public.inventory_transaction_lines for select to authenticated using (private.has_permission('warehouse') or private.is_manager());
create policy sales_select on public.sales for select to authenticated using (private.has_permission('sales') or private.is_manager());
create policy sale_lines_select on public.sale_lines for select to authenticated using (private.has_permission('sales') or private.is_manager());
create policy accounts_select on public.financial_accounts for select to authenticated using (private.has_permission('finance') or private.is_manager());
create policy financial_select on public.financial_transactions for select to authenticated using (private.has_permission('finance') or private.is_manager());
create policy expenses_select on public.expenses for select to authenticated using (private.has_permission('finance') or private.is_manager());
create policy workers_select on public.workers for select to authenticated using (private.has_permission('payroll') or private.is_manager());
create policy advances_select on public.worker_advances for select to authenticated using (private.has_permission('payroll') or private.is_manager());
create policy payroll_runs_select on public.payroll_runs for select to authenticated using (private.has_permission('payroll') or private.is_manager());
create policy payroll_entries_select on public.payroll_entries for select to authenticated using (private.has_permission('payroll') or private.is_manager());
create policy audit_select on public.audit_logs for select to authenticated using (private.is_manager());

-- سياسات INSERT: المسودات فقط، والاعتماد لا يتم بتحديث مباشر.
create policy profiles_insert on public.profiles for insert to authenticated with check (private.is_manager() or id=auth.uid());
create policy units_insert on public.units for insert to authenticated with check (private.has_permission('warehouse'));
create policy warehouses_insert on public.warehouses for insert to authenticated with check (private.has_permission('warehouse'));
create policy items_insert on public.items for insert to authenticated with check (private.has_permission('warehouse'));
create policy item_conversions_insert on public.item_unit_conversions for insert to authenticated with check (private.has_permission('warehouse'));
create policy customers_insert on public.customers for insert to authenticated with check (private.has_permission('sales'));
create policy suppliers_insert on public.suppliers for insert to authenticated with check (private.has_permission('warehouse'));
create policy inventory_insert on public.inventory_transactions for insert to authenticated with check (status='draft' and private.has_permission('warehouse'));
create policy inventory_lines_insert on public.inventory_transaction_lines for insert to authenticated with check (private.has_permission('warehouse'));
create policy sales_insert on public.sales for insert to authenticated with check (status='draft' and private.has_permission('sales'));
create policy sale_lines_insert on public.sale_lines for insert to authenticated with check (exists(select 1 from public.sales s where s.id=sale_id and s.status='draft' and private.has_permission('sales')));
create policy accounts_insert on public.financial_accounts for insert to authenticated with check (private.has_permission('finance'));
create policy financial_insert on public.financial_transactions for insert to authenticated with check (status='draft' and private.has_permission('finance'));
create policy expenses_insert on public.expenses for insert to authenticated with check (status='draft' and private.has_permission('finance'));
create policy workers_insert on public.workers for insert to authenticated with check (private.has_permission('payroll'));
create policy advances_insert on public.worker_advances for insert to authenticated with check (status='draft' and private.has_permission('payroll'));
create policy payroll_runs_insert on public.payroll_runs for insert to authenticated with check (status='draft' and private.has_permission('payroll'));

-- سياسات UPDATE منفصلة: المسودات فقط، وإدارة الأدوار عبر RPC.
create policy profiles_update on public.profiles for update to authenticated using (private.is_manager() and id<>auth.uid()) with check (private.is_manager() and id<>auth.uid());
create policy warehouses_update on public.warehouses for update to authenticated using (private.has_permission('warehouse')) with check (private.has_permission('warehouse'));
create policy items_update on public.items for update to authenticated using (private.has_permission('warehouse')) with check (private.has_permission('warehouse'));
create policy customers_update on public.customers for update to authenticated using (private.has_permission('sales')) with check (private.has_permission('sales'));
create policy suppliers_update on public.suppliers for update to authenticated using (private.has_permission('warehouse')) with check (private.has_permission('warehouse'));
create policy inventory_update on public.inventory_transactions for update to authenticated using (status='draft' and private.has_permission('warehouse')) with check (status='draft' and private.has_permission('warehouse'));
create policy sales_update on public.sales for update to authenticated using (status='draft' and private.has_permission('sales')) with check (status='draft' and private.has_permission('sales'));
create policy sale_lines_update on public.sale_lines for update to authenticated using (exists(select 1 from public.sales s where s.id=sale_id and s.status='draft' and private.has_permission('sales'))) with check (exists(select 1 from public.sales s where s.id=sale_id and s.status='draft' and private.has_permission('sales')));
create policy accounts_update on public.financial_accounts for update to authenticated using (private.has_permission('finance')) with check (private.has_permission('finance'));
create policy financial_update on public.financial_transactions for update to authenticated using (status='draft' and private.has_permission('finance')) with check (status='draft' and private.has_permission('finance'));
create policy expenses_update on public.expenses for update to authenticated using (status='draft' and private.has_permission('finance')) with check (status='draft' and private.has_permission('finance'));
create policy workers_update on public.workers for update to authenticated using (private.has_permission('payroll')) with check (private.has_permission('payroll'));
create policy advances_update on public.worker_advances for update to authenticated using (status='draft' and private.has_permission('payroll')) with check (status='draft' and private.has_permission('payroll'));
create policy payroll_runs_update on public.payroll_runs for update to authenticated using (status='draft' and private.has_permission('payroll')) with check (status='draft' and private.has_permission('payroll'));

-- لا حذف للمستندات المالية أو المخزون أو الرواتب؛ الحذف المباشر مقتصر على السجلات غير المرحّلة عند الحاجة.
create policy warehouses_delete on public.warehouses for delete to authenticated using (private.has_permission('warehouse') and not exists(select 1 from public.inventory_transactions t where t.warehouse_id=id));
create policy items_delete on public.items for delete to authenticated using (private.has_permission('warehouse') and not exists(select 1 from public.inventory_transactions t where t.item_id=id));
create policy customers_delete on public.customers for delete to authenticated using (private.has_permission('sales') and not exists(select 1 from public.sales s where s.customer_id=id));
create policy suppliers_delete on public.suppliers for delete to authenticated using (private.has_permission('warehouse'));
create policy inventory_delete on public.inventory_transactions for delete to authenticated using (status='draft' and private.has_permission('warehouse'));
create policy sale_lines_delete on public.sale_lines for delete to authenticated using (exists(select 1 from public.sales s where s.id=sale_id and s.status='draft' and private.has_permission('sales')));
create policy sales_delete on public.sales for delete to authenticated using (status='draft' and private.has_permission('sales'));
create policy accounts_delete on public.financial_accounts for delete to authenticated using (private.has_permission('finance') and not exists(select 1 from public.financial_transactions t where t.financial_account_id=id));
create policy financial_delete on public.financial_transactions for delete to authenticated using (status='draft' and private.has_permission('finance'));
create policy expenses_delete on public.expenses for delete to authenticated using (status='draft' and private.has_permission('finance'));
create policy workers_delete on public.workers for delete to authenticated using (private.has_permission('payroll') and not exists(select 1 from public.payroll_entries p where p.worker_id=id));
create policy advances_delete on public.worker_advances for delete to authenticated using (status='draft' and private.has_permission('payroll'));
create policy payroll_runs_delete on public.payroll_runs for delete to authenticated using (status='draft' and private.has_permission('payroll'));

-- لا تعرض أي دالة إدارية عامة غير مطلوبة.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function public.dashboard_summary() to authenticated;
grant execute on function public.approve_inventory_transaction(uuid,text) to authenticated;
grant execute on function public.approve_financial_transaction(uuid,text) to authenticated;
grant execute on function public.approve_expense(uuid,text) to authenticated;
grant execute on function public.approve_sale(uuid) to authenticated;
grant execute on function public.change_item_price(uuid,text,numeric,text) to authenticated;
grant execute on function public.create_payroll_run(text,date,date,jsonb) to authenticated;
grant execute on function public.approve_payroll_run(uuid) to authenticated;
grant execute on function public.pay_payroll_entry(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.cancel_document(text,uuid,text) to authenticated;
grant execute on function public.change_user_role(uuid,public.app_role,text) to authenticated;
grant execute on function public.complete_password_change() to authenticated;
grant execute on function public.daily_reconciliation(date,date) to authenticated;
