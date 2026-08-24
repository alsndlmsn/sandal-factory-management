-- Al Sandal Plastic Factory Management System v2
-- Arabic UI, secure Supabase schema, flexible permissions, controlled financial and stock movements.

create extension if not exists pgcrypto;
create extension if not exists citext;

create type public.app_role as enum ('manager','finance','sales','inventory','production');
create type public.employee_status as enum ('active','suspended','on_leave','left_work','archived');
create type public.wage_type as enum ('monthly','daily','hourly');
create type public.attendance_status as enum ('present','absent','late','leave','excused','half_day','missing_checkout');
create type public.document_status as enum ('draft','pending','approved','cancelled','paid','partially_paid');
create type public.product_type as enum ('raw_material','finished_product');
create type public.payment_method as enum ('cash','bank');
create type public.movement_direction as enum ('in','out');
create type public.advance_status as enum ('not_deducted','partially_deducted','fully_deducted');

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code public.app_role unique not null,
  name_ar text not null,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name_ar text not null,
  module text not null,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email citext unique,
  full_name text not null default '',
  is_enabled boolean not null default true,
  must_change_password boolean not null default false,
  last_sign_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  assigned_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

create table public.settings (
  key text primary key,
  value_json jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table public.departments (
  id uuid primary key default gen_random_uuid(), name text unique not null, is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.job_titles (
  id uuid primary key default gen_random_uuid(), name text unique not null, is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.shifts (
  id uuid primary key default gen_random_uuid(), name text unique not null, start_time time not null, end_time time not null,
  crosses_midnight boolean not null default false, overtime_after_minutes integer not null default 0 check (overtime_after_minutes >= 0),
  is_active boolean not null default true, created_at timestamptz not null default now()
);

create sequence public.employee_number_seq start 1;
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_number text unique not null default ('SD-EMP-' || lpad(nextval('public.employee_number_seq')::text, 4, '0')),
  full_name text not null,
  phone text, department_id uuid references public.departments(id) on delete restrict,
  job_title_id uuid references public.job_titles(id) on delete restrict,
  employment_date date not null default current_date,
  wage_type public.wage_type not null default 'monthly',
  base_salary numeric(18,2) not null default 0 check (base_salary >= 0),
  default_shift_id uuid references public.shifts(id) on delete restrict,
  status public.employee_status not null default 'active', notes text,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.employee_history (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
  field_name text not null, old_value jsonb, new_value jsonb, changed_by uuid not null references public.profiles(id),
  reason text, created_at timestamptz not null default now()
);

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
  shift_id uuid references public.shifts(id) on delete restrict, status public.attendance_status not null default 'present',
  check_in_at timestamptz, check_out_at timestamptz, working_minutes integer generated always as (
    case when check_in_at is not null and check_out_at is not null then greatest(0, floor(extract(epoch from (check_out_at - check_in_at))/60)::integer) else null end
  ) stored,
  overtime_minutes integer not null default 0 check (overtime_minutes >= 0), notes text, recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create unique index idx_attendance_employee_local_day on public.attendance_records(employee_id, ((check_in_at at time zone 'Africa/Khartoum')::date)) where check_in_at is not null;

create table public.attendance_corrections (
  id uuid primary key default gen_random_uuid(), attendance_id uuid not null references public.attendance_records(id) on delete restrict,
  old_check_in_at timestamptz, old_check_out_at timestamptz, new_check_in_at timestamptz, new_check_out_at timestamptz,
  reason text not null check (length(btrim(reason)) >= 3), corrected_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.product_categories (
  id uuid primary key default gen_random_uuid(), name text unique not null, product_type public.product_type not null,
  is_active boolean not null default true, created_at timestamptz not null default now()
);

create table public.units (
  code text primary key, name_ar text not null, is_active boolean not null default true
);

create table public.products (
  id uuid primary key default gen_random_uuid(), name text not null, code text unique, category_id uuid references public.product_categories(id) on delete restrict,
  product_type public.product_type not null, unit_code text not null references public.units(code), purchase_price numeric(18,2) not null default 0 check (purchase_price >= 0),
  sale_price numeric(18,2) not null default 0 check (sale_price >= 0), minimum_stock numeric(18,3) not null default 0 check (minimum_stock >= 0),
  notes text, is_active boolean not null default true, created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(), name text unique not null, code text unique, address text, is_active boolean not null default true,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(), document_number text unique not null, direction public.movement_direction not null,
  movement_type text not null, warehouse_id uuid not null references public.warehouses(id) on delete restrict, related_production_id uuid,
  related_sale_id uuid, movement_date timestamptz not null default now(), status public.document_status not null default 'draft',
  notes text, created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.stock_movement_lines (
  id uuid primary key default gen_random_uuid(), movement_id uuid not null references public.stock_movements(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict, quantity numeric(18,3) not null check (quantity > 0),
  unit_code text not null references public.units(code), unit_cost numeric(18,2) not null default 0 check (unit_cost >= 0), notes text
);

create table public.production_orders (
  id uuid primary key default gen_random_uuid(), order_number text unique not null, product_id uuid not null references public.products(id) on delete restrict,
  production_date date not null default current_date, shift_id uuid references public.shifts(id) on delete restrict, supervisor_employee_id uuid references public.employees(id) on delete restrict,
  planned_quantity numeric(18,3) not null check (planned_quantity > 0), actual_quantity numeric(18,3) not null default 0 check (actual_quantity >= 0),
  damaged_quantity numeric(18,3) not null default 0 check (damaged_quantity >= 0), accepted_quantity numeric(18,3) generated always as (greatest(0, actual_quantity - damaged_quantity)) stored,
  status public.document_status not null default 'draft', notes text, created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check (damaged_quantity <= actual_quantity)
);

create table public.production_materials (
  id uuid primary key default gen_random_uuid(), production_order_id uuid not null references public.production_orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict, required_quantity numeric(18,3) not null check (required_quantity > 0), issued_quantity numeric(18,3) not null default 0 check (issued_quantity >= 0)
);

create table public.production_outputs (
  id uuid primary key default gen_random_uuid(), production_order_id uuid not null references public.production_orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict, accepted_quantity numeric(18,3) not null check (accepted_quantity >= 0), damaged_quantity numeric(18,3) not null default 0 check (damaged_quantity >= 0)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(), name text not null, phone text, email citext, address text, notes text,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.banks (
  id uuid primary key default gen_random_uuid(), name text unique not null, account_number_masked text, is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.cash_registers (
  id uuid primary key default gen_random_uuid(), name text unique not null, opening_balance numeric(18,2) not null default 0 check (opening_balance >= 0),
  is_active boolean not null default true, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);

create table public.sales (
  id uuid primary key default gen_random_uuid(), invoice_number text unique not null, customer_id uuid references public.customers(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict, payment_method public.payment_method not null,
  cash_register_id uuid references public.cash_registers(id) on delete restrict, bank_id uuid references public.banks(id) on delete restrict,
  bank_transaction_number text, sold_at timestamptz not null default now(), subtotal numeric(18,2) not null default 0 check (subtotal >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0), total numeric(18,2) not null default 0 check (total >= 0),
  status public.document_status not null default 'draft', notes text, created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((payment_method='cash' and cash_register_id is not null and bank_id is null) or (payment_method='bank' and bank_id is not null and length(btrim(coalesce(bank_transaction_number,''))) >= 3))
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(), sale_id uuid not null references public.sales(id) on delete restrict, product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0), unit_code text not null references public.units(code), unit_price numeric(18,2) not null check (unit_price >= 0),
  unit_cost numeric(18,2) not null default 0 check (unit_cost >= 0), discount numeric(18,2) not null default 0 check (discount >= 0),
  line_total numeric(18,2) generated always as ((quantity * unit_price) - discount) stored, check ((quantity * unit_price) >= discount)
);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(), name text unique not null, is_active boolean not null default true, created_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(), expense_number text unique not null, category_id uuid not null references public.expense_categories(id) on delete restrict,
  department_id uuid references public.departments(id) on delete restrict, amount numeric(18,2) not null check (amount > 0), payment_method public.payment_method not null,
  cash_register_id uuid references public.cash_registers(id) on delete restrict, bank_id uuid references public.banks(id) on delete restrict, bank_transaction_number text,
  expense_date timestamptz not null default now(), description text, status public.document_status not null default 'draft', created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz,
  created_at timestamptz not null default now(), check ((payment_method='cash' and cash_register_id is not null and bank_id is null) or (payment_method='bank' and bank_id is not null and length(btrim(coalesce(bank_transaction_number,''))) >= 3))
);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(), transaction_number text unique not null, cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  direction public.movement_direction not null, transaction_type text not null, amount numeric(18,2) not null check (amount > 0), related_entity text, related_id uuid,
  transaction_at timestamptz not null default now(), notes text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.bank_transactions (
  id uuid primary key default gen_random_uuid(), transaction_number text unique not null, bank_id uuid not null references public.banks(id) on delete restrict,
  direction public.movement_direction not null, transaction_type text not null, amount numeric(18,2) not null check (amount > 0), related_entity text, related_id uuid,
  transaction_at timestamptz not null default now(), notes text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.employee_advances (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict, advance_number text unique not null,
  amount numeric(18,2) not null check (amount > 0), advance_date timestamptz not null default now(), deducted_amount numeric(18,2) not null default 0 check (deducted_amount >= 0 and deducted_amount <= amount),
  status public.advance_status generated always as (case when deducted_amount=0 then 'not_deducted'::public.advance_status when deducted_amount < amount then 'partially_deducted'::public.advance_status else 'fully_deducted'::public.advance_status end) stored,
  notes text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.payroll_periods (
  id uuid primary key default gen_random_uuid(), period_number text unique not null, period_start date not null, period_end date not null,
  status public.document_status not null default 'draft', created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz,
  created_at timestamptz not null default now(), unique(period_start, period_end), check (period_end >= period_start)
);

create table public.payroll_records (
  id uuid primary key default gen_random_uuid(), payroll_period_id uuid not null references public.payroll_periods(id) on delete restrict, employee_id uuid not null references public.employees(id) on delete restrict,
  basic_salary numeric(18,2) not null default 0 check (basic_salary >= 0), overtime numeric(18,2) not null default 0 check (overtime >= 0), bonuses numeric(18,2) not null default 0 check (bonuses >= 0),
  deductions numeric(18,2) not null default 0 check (deductions >= 0), advances_deducted numeric(18,2) not null default 0 check (advances_deducted >= 0),
  net_salary numeric(18,2) generated always as (basic_salary + overtime + bonuses - deductions - advances_deducted) stored,
  paid_amount numeric(18,2) not null default 0 check (paid_amount >= 0), payment_status public.document_status not null default 'draft', notes text,
  unique(payroll_period_id, employee_id), check (basic_salary + overtime + bonuses >= deductions + advances_deducted), check (paid_amount <= basic_salary + overtime + bonuses - deductions - advances_deducted)
);

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id), action text not null, entity_type text not null, entity_id uuid,
  old_data jsonb, new_data jsonb, reason text, severity text not null default 'normal', created_at timestamptz not null default now()
);

create index idx_attendance_employee_date on public.attendance_records(employee_id, check_in_at desc);
create index idx_products_type on public.products(product_type, is_active);
create index idx_stock_movements_date on public.stock_movements(movement_date desc);
create index idx_sales_date on public.sales(sold_at desc);
create index idx_expenses_date on public.expenses(expense_date desc);
create index idx_cash_transactions_date on public.cash_transactions(transaction_at desc);
create index idx_bank_transactions_date on public.bank_transactions(transaction_at desc);
create index idx_advances_employee on public.employee_advances(employee_id, advance_date desc);
create index idx_activity_logs_entity on public.activity_logs(entity_type, entity_id, created_at desc);

insert into public.units(code,name_ar) values ('piece','قطعة'),('kilogram','كيلوجرام'),('roll','لفة'),('carton','كرتونة'),('bundle','ربطة') on conflict (code) do nothing;
insert into public.roles(code,name_ar,description) values ('manager','المدير','صلاحية كاملة'),('finance','الحسابات والخزنة والمرتبات','المالية والموظفون والمرتبات'),('sales','المبيعات','المبيعات والعملاء'),('inventory','المخزن','المخزون والصادر والوارد'),('production','الإنتاج','الإنتاج والمواد') on conflict (code) do nothing;

create or replace function public.current_user_has_permission(p_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id where ur.user_id=auth.uid() and p.code=p_code)
  or exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=auth.uid() and r.code='manager');
$$;

create or replace function public.current_user_is_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=auth.uid() and r.code='manager');
$$;

create or replace function public.stock_balance(p_product_id uuid, p_warehouse_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when sm.direction='in' then sml.quantity else -sml.quantity end),0)
  from public.stock_movements sm join public.stock_movement_lines sml on sml.movement_id=sm.id
  where sm.status='approved' and sml.product_id=p_product_id and sm.warehouse_id=p_warehouse_id;
$$;

create or replace view public.v_stock_balances as
select p.id product_id, p.name product_name, p.product_type, p.unit_code, p.minimum_stock, w.id warehouse_id, w.name warehouse_name,
       coalesce(sum(case when sm.direction='in' then sml.quantity when sm.direction='out' then -sml.quantity else 0 end),0)::numeric(18,3) balance
from public.products p cross join public.warehouses w left join public.stock_movements sm on sm.warehouse_id=w.id and sm.status='approved'
left join public.stock_movement_lines sml on sml.movement_id=sm.id and sml.product_id=p.id where p.is_active and w.is_active group by p.id,p.name,p.product_type,p.unit_code,p.minimum_stock,w.id,w.name;

create or replace view public.v_cash_balances as
select cr.id cash_register_id, cr.name, cr.opening_balance + coalesce(sum(case when ct.direction='in' then ct.amount else -ct.amount end),0)::numeric(18,2) balance
from public.cash_registers cr left join public.cash_transactions ct on ct.cash_register_id=cr.id group by cr.id,cr.name,cr.opening_balance;

create or replace function public.manager_dashboard_summary()
returns json language plpgsql stable security definer set search_path = public as $$
declare result json; d date := (now() at time zone 'Africa/Khartoum')::date;
begin
  if auth.uid() is null or not public.current_user_has_permission('reports.view') then raise exception 'غير مصرح'; end if;
  select json_build_object(
    'today_sales', coalesce((select sum(total) from sales where status='approved' and (sold_at at time zone 'Africa/Khartoum')::date=d),0),
    'monthly_sales', coalesce((select sum(total) from sales where status='approved' and date_trunc('month',sold_at at time zone 'Africa/Khartoum')=date_trunc('month',now() at time zone 'Africa/Khartoum')),0),
    'today_expenses', coalesce((select sum(amount) from expenses where status='approved' and (expense_date at time zone 'Africa/Khartoum')::date=d),0),
    'today_cost', coalesce((select sum(si.quantity*si.unit_cost) from sales s join sale_items si on si.sale_id=s.id where s.status='approved' and (s.sold_at at time zone 'Africa/Khartoum')::date=d),0),
    'cash_balance', coalesce((select sum(balance) from v_cash_balances),0),
    'total_employees', (select count(*) from employees where status='active'),
    'present_today', (select count(*) from attendance_records where (check_in_at at time zone 'Africa/Khartoum')::date=d and status in ('present','late','half_day')),
    'absent_today', (select count(*) from employees where status='active') - (select count(*) from attendance_records where (check_in_at at time zone 'Africa/Khartoum')::date=d and status in ('present','late','half_day')),
    'missing_checkout', (select count(*) from attendance_records where (check_in_at at time zone 'Africa/Khartoum')::date=d and check_in_at is not null and check_out_at is null),
    'today_production', coalesce((select sum(accepted_quantity) from production_orders where status='approved' and production_date=d),0),
    'low_stock_count', (select count(*) from v_stock_balances where balance < minimum_stock)
  ) into result; return result;
end; $$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles(id,email,full_name) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name','')) on conflict (id) do nothing; return new; end; $$;
create or replace trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.settings enable row level security;
alter table public.departments enable row level security;
alter table public.job_titles enable row level security;
alter table public.shifts enable row level security;
alter table public.employees enable row level security;
alter table public.employee_history enable row level security;
alter table public.attendance_records enable row level security;
alter table public.attendance_corrections enable row level security;
alter table public.product_categories enable row level security;
alter table public.units enable row level security;
alter table public.products enable row level security;
alter table public.warehouses enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_movement_lines enable row level security;
alter table public.production_orders enable row level security;
alter table public.production_materials enable row level security;
alter table public.production_outputs enable row level security;
alter table public.customers enable row level security;
alter table public.banks enable row level security;
alter table public.cash_registers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.cash_transactions enable row level security;
alter table public.bank_transactions enable row level security;
alter table public.employee_advances enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_records enable row level security;
alter table public.activity_logs enable row level security;

-- Broad read policies are still restricted by authenticated access; write and approval paths are tightened by permission checks and RPCs in production migrations.
create policy profiles_self_or_manager on public.profiles for select to authenticated using (id=auth.uid() or public.current_user_is_manager());
create policy profiles_manager_update on public.profiles for update to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy user_roles_manager on public.user_roles for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy roles_read_auth on public.roles for select to authenticated using (auth.uid() is not null);
create policy permissions_read_auth on public.permissions for select to authenticated using (auth.uid() is not null);
create policy role_permissions_read_auth on public.role_permissions for select to authenticated using (auth.uid() is not null);
create policy settings_manager on public.settings for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy employees_read_permission on public.employees for select to authenticated using (public.current_user_has_permission('employees.view'));
create policy employees_write_permission on public.employees for insert to authenticated with check (public.current_user_has_permission('employees.create'));
create policy employees_update_permission on public.employees for update to authenticated using (public.current_user_has_permission('employees.edit')) with check (public.current_user_has_permission('employees.edit'));
create policy products_read_permission on public.products for select to authenticated using (public.current_user_has_permission('inventory.view') or public.current_user_has_permission('sales.view') or public.current_user_has_permission('production.view'));
create policy warehouses_read_permission on public.warehouses for select to authenticated using (public.current_user_has_permission('inventory.view') or public.current_user_has_permission('sales.view'));
create policy customers_sales_read on public.customers for select to authenticated using (public.current_user_has_permission('sales.view'));
create policy sales_sales_read on public.sales for select to authenticated using (public.current_user_has_permission('sales.view') or public.current_user_is_manager());
create policy expenses_finance_read on public.expenses for select to authenticated using (public.current_user_has_permission('expenses.view') or public.current_user_is_manager());
create policy advances_finance_read on public.employee_advances for select to authenticated using (public.current_user_has_permission('payroll.view') or public.current_user_is_manager());
create policy attendance_read_permission on public.attendance_records for select to authenticated using (public.current_user_has_permission('attendance.view') or public.current_user_is_manager());
create policy activity_manager_read on public.activity_logs for select to authenticated using (public.current_user_is_manager());

revoke all on schema public from anon;
grant usage on schema public to authenticated;
revoke all on all tables in schema public from anon;
