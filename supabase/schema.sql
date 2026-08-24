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
insert into public.roles(code,name_ar,description) values ('manager','المدير','صلاحية كاملة'),('finance','الحسابات والخزنة والمرتبات','المالية والموظفون والمرتبات'),('sales','المبيعات','المبيعات والعملاء'),('inventory','المخزن','المخزون والصادر والوارد'),('production','الإنتاج','الإنتاج والمواد') on conflict (code) do update set name_ar=excluded.name_ar, description=excluded.description;
insert into public.permissions(code,name_ar,module) values
 ('dashboard.view','لوحة اليوم','dashboard'),('reports.view','عرض التقارير','reports'),('reports.print','طباعة التقارير','reports'),
 ('employees.view','عرض الموظفين','employees'),('employees.create','إضافة موظف','employees'),('employees.edit','تعديل موظف','employees'),('attendance.view','عرض الحضور','attendance'),('attendance.create','تسجيل الحضور','attendance'),('attendance.correct','تصحيح الحضور','attendance'),
 ('inventory.view','عرض المخزن','inventory'),('inventory.create','تسجيل حركة مخزن','inventory'),('inventory.approve','اعتماد حركة مخزن','inventory'),('products.manage','إدارة المنتجات','inventory'),
 ('production.view','عرض الإنتاج','production'),('production.create','إنشاء أمر إنتاج','production'),('production.approve','اعتماد الإنتاج','production'),
 ('sales.view','عرض المبيعات','sales'),('sales.create','إنشاء فاتورة','sales'),('sales.approve','اعتماد البيع','sales'),('customers.manage','إدارة العملاء','sales'),
 ('expenses.view','عرض المنصرفات','finance'),('expenses.create','تسجيل منصرف','finance'),('expenses.approve','اعتماد منصرف','finance'),('cash.manage','إدارة الخزنة','finance'),('bank.manage','إدارة البنوك','finance'),
 ('payroll.view','عرض المرتبات','payroll'),('payroll.manage','إدارة المرتبات والسلفيات','payroll'),('settings.manage','إدارة الإعدادات','settings')
 on conflict (code) do update set name_ar=excluded.name_ar,module=excluded.module;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p where r.code='manager' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('dashboard.view','reports.view','reports.print','employees.view','employees.create','employees.edit','attendance.view','attendance.create','attendance.correct','expenses.view','expenses.create','expenses.approve','cash.manage','bank.manage','payroll.view','payroll.manage') where r.code='finance' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('dashboard.view','sales.view','sales.create','sales.approve','customers.manage','inventory.view') where r.code='sales' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('dashboard.view','inventory.view','inventory.create','inventory.approve','products.manage') where r.code='inventory' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('dashboard.view','production.view','production.create','production.approve','inventory.view') where r.code='production' on conflict do nothing;

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
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

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

-- Policies for reference and master data.
create policy departments_read on public.departments for select to authenticated using (public.current_user_has_permission('employees.view'));
create policy departments_manage on public.departments for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy job_titles_read on public.job_titles for select to authenticated using (public.current_user_has_permission('employees.view'));
create policy job_titles_manage on public.job_titles for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy shifts_read on public.shifts for select to authenticated using (public.current_user_has_permission('attendance.view') or public.current_user_has_permission('employees.view'));
create policy shifts_manage on public.shifts for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy units_read on public.units for select to authenticated using (auth.uid() is not null);
create policy categories_inventory_read on public.product_categories for select to authenticated using (public.current_user_has_permission('inventory.view') or public.current_user_has_permission('sales.view') or public.current_user_has_permission('production.view'));
create policy categories_manager_write on public.product_categories for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy cash_registers_read on public.cash_registers for select to authenticated using (public.current_user_has_permission('cash.manage') or public.current_user_has_permission('sales.view'));
create policy cash_registers_manager_write on public.cash_registers for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy banks_read on public.banks for select to authenticated using (public.current_user_has_permission('bank.manage') or public.current_user_has_permission('sales.view'));
create policy banks_manager_write on public.banks for all to authenticated using (public.current_user_is_manager()) with check (public.current_user_is_manager());
create policy product_write_permission on public.products for all to authenticated using (public.current_user_has_permission('products.manage')) with check (public.current_user_has_permission('products.manage'));
create policy warehouse_write_permission on public.warehouses for all to authenticated using (public.current_user_is_manager() or public.current_user_has_permission('inventory.create')) with check (public.current_user_is_manager() or public.current_user_has_permission('inventory.create'));
create policy customers_write_permission on public.customers for all to authenticated using (public.current_user_has_permission('customers.manage')) with check (public.current_user_has_permission('customers.manage'));
create policy stock_movements_create on public.stock_movements for insert to authenticated with check (public.current_user_has_permission('inventory.create') and created_by=auth.uid());
create policy stock_movements_read on public.stock_movements for select to authenticated using (public.current_user_has_permission('inventory.view'));
create policy stock_movements_approve_update on public.stock_movements for update to authenticated using (public.current_user_has_permission('inventory.approve')) with check (public.current_user_has_permission('inventory.approve'));
create policy stock_lines_read on public.stock_movement_lines for select to authenticated using (public.current_user_has_permission('inventory.view'));
create policy stock_lines_create on public.stock_movement_lines for insert to authenticated with check (public.current_user_has_permission('inventory.create'));
create policy production_read on public.production_orders for select to authenticated using (public.current_user_has_permission('production.view'));
create policy production_create on public.production_orders for insert to authenticated with check (public.current_user_has_permission('production.create') and created_by=auth.uid());
create policy production_approve on public.production_orders for update to authenticated using (public.current_user_has_permission('production.approve')) with check (public.current_user_has_permission('production.approve'));
create policy production_children_read on public.production_materials for select to authenticated using (public.current_user_has_permission('production.view'));
create policy production_children_write on public.production_materials for all to authenticated using (public.current_user_has_permission('production.create')) with check (public.current_user_has_permission('production.create'));
create policy production_outputs_read on public.production_outputs for select to authenticated using (public.current_user_has_permission('production.view'));
create policy production_outputs_write on public.production_outputs for all to authenticated using (public.current_user_has_permission('production.create')) with check (public.current_user_has_permission('production.create'));
create policy sale_items_read on public.sale_items for select to authenticated using (public.current_user_has_permission('sales.view'));
create policy sale_items_create on public.sale_items for insert to authenticated with check (public.current_user_has_permission('sales.create'));
create policy sales_create on public.sales for insert to authenticated with check (public.current_user_has_permission('sales.create') and created_by=auth.uid());
create policy sales_approve on public.sales for update to authenticated using (public.current_user_has_permission('sales.approve')) with check (public.current_user_has_permission('sales.approve'));
create policy expense_create on public.expenses for insert to authenticated with check (public.current_user_has_permission('expenses.create') and created_by=auth.uid());
create policy expense_approve on public.expenses for update to authenticated using (public.current_user_has_permission('expenses.approve')) with check (public.current_user_has_permission('expenses.approve'));
create policy cash_transactions_read on public.cash_transactions for select to authenticated using (public.current_user_has_permission('cash.manage') or public.current_user_has_permission('reports.view'));
create policy bank_transactions_read on public.bank_transactions for select to authenticated using (public.current_user_has_permission('bank.manage') or public.current_user_has_permission('reports.view'));
create policy advances_create on public.employee_advances for insert to authenticated with check (public.current_user_has_permission('payroll.manage') and created_by=auth.uid());
create policy payroll_period_read on public.payroll_periods for select to authenticated using (public.current_user_has_permission('payroll.view'));
create policy payroll_period_manage on public.payroll_periods for all to authenticated using (public.current_user_has_permission('payroll.manage')) with check (public.current_user_has_permission('payroll.manage'));
create policy payroll_records_read on public.payroll_records for select to authenticated using (public.current_user_has_permission('payroll.view'));
create policy payroll_records_manage on public.payroll_records for all to authenticated using (public.current_user_has_permission('payroll.manage')) with check (public.current_user_has_permission('payroll.manage'));

-- Generic audit trigger. It records the acting authenticated user and old/new row snapshots.
create or replace function public.write_activity_log() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op='INSERT' then insert into public.activity_logs(actor_id,action,entity_type,entity_id,new_data) values (auth.uid(),tg_op,tg_table_name,new.id,to_jsonb(new)); return new;
  elsif tg_op='UPDATE' then insert into public.activity_logs(actor_id,action,entity_type,entity_id,old_data,new_data) values (auth.uid(),tg_op,tg_table_name,new.id,to_jsonb(old),to_jsonb(new)); return new;
  else insert into public.activity_logs(actor_id,action,entity_type,entity_id,old_data) values (auth.uid(),tg_op,tg_table_name,old.id,to_jsonb(old)); return old; end if;
end; $$;
drop trigger if exists audit_sales on public.sales;
create trigger audit_sales after insert or update or delete on public.sales for each row execute function public.write_activity_log();
drop trigger if exists audit_expenses on public.expenses;
create trigger audit_expenses after insert or update or delete on public.expenses for each row execute function public.write_activity_log();
drop trigger if exists audit_stock_movements on public.stock_movements;
create trigger audit_stock_movements after insert or update or delete on public.stock_movements for each row execute function public.write_activity_log();
drop trigger if exists audit_employees on public.employees;
create trigger audit_employees after insert or update or delete on public.employees for each row execute function public.write_activity_log();

-- Atomic approval routines. They are the only paths that change stock and cash ledgers.
create or replace function public.approve_sale(p_sale_id uuid) returns public.sales language plpgsql security definer set search_path = public as $$
declare s public.sales; item record; balance numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.approve') then raise exception 'غير مصرح باعتماد البيع'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if s.id is null or s.status <> 'draft' then raise exception 'الفاتورة غير قابلة للاعتماد'; end if;
  for item in select * from public.sale_items where sale_id=p_sale_id loop
    balance := public.stock_balance(item.product_id,s.warehouse_id);
    if balance < item.quantity then raise exception 'الرصيد غير كاف للصنف'; end if;
  end loop;
  update public.sales set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_sale_id returning * into s;
  insert into public.cash_transactions(transaction_number,cash_register_id,direction,transaction_type,amount,related_entity,related_id,created_by)
    select 'SALE-'||s.invoice_number,s.cash_register_id,'in','sale',s.total,'sales',s.id,auth.uid() where s.payment_method='cash';
  insert into public.bank_transactions(transaction_number,bank_id,direction,transaction_type,amount,related_entity,related_id,created_by)
    select coalesce(s.bank_transaction_number,'SALE-'||s.invoice_number),s.bank_id,'in','sale',s.total,'sales',s.id,auth.uid() where s.payment_method='bank';
  return s;
end; $$;

create or replace function public.approve_stock_movement(p_movement_id uuid) returns public.stock_movements language plpgsql security definer set search_path = public as $$
declare m public.stock_movements; line record; bal numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('inventory.approve') then raise exception 'غير مصرح باعتماد حركة المخزن'; end if;
  select * into m from public.stock_movements where id=p_movement_id for update;
  if m.id is null or m.status <> 'draft' then raise exception 'الحركة غير قابلة للاعتماد'; end if;
  if m.direction='out' then for line in select * from public.stock_movement_lines where movement_id=p_movement_id loop bal:=public.stock_balance(line.product_id,m.warehouse_id); if bal < line.quantity then raise exception 'الرصيد غير كاف للصنف'; end if; end loop; end if;
  update public.stock_movements set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_movement_id returning * into m;
  return m;
end; $$;

create or replace function public.approve_expense(p_expense_id uuid) returns public.expenses language plpgsql security definer set search_path = public as $$
declare e public.expenses;
begin
  if auth.uid() is null or not public.current_user_has_permission('expenses.approve') then raise exception 'غير مصرح باعتماد المنصرف'; end if;
  select * into e from public.expenses where id=p_expense_id for update;
  if e.id is null or e.status <> 'draft' then raise exception 'المنصرف غير قابل للاعتماد'; end if;
  update public.expenses set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_expense_id returning * into e;
  if e.payment_method='cash' then insert into public.cash_transactions(transaction_number,cash_register_id,direction,transaction_type,amount,related_entity,related_id,notes,created_by) values ('EXP-'||e.expense_number,e.cash_register_id,'out','expense',e.amount,'expenses',e.id,e.description,auth.uid());
  else insert into public.bank_transactions(transaction_number,bank_id,direction,transaction_type,amount,related_entity,related_id,notes,created_by) values (coalesce(e.bank_transaction_number,'EXP-'||e.expense_number),e.bank_id,'out','expense',e.amount,'expenses',e.id,e.description,auth.uid()); end if;
  return e;
end; $$;

create or replace function public.record_cash_transaction(p_transaction_number text,p_cash_register_id uuid,p_direction public.movement_direction,p_transaction_type text,p_amount numeric,p_notes text default null) returns public.cash_transactions language plpgsql security definer set search_path = public as $$
declare t public.cash_transactions;
begin
  if auth.uid() is null or not public.current_user_has_permission('cash.manage') then raise exception 'غير مصرح بحركة الخزنة'; end if;
  insert into public.cash_transactions(transaction_number,cash_register_id,direction,transaction_type,amount,notes,created_by) values(p_transaction_number,p_cash_register_id,p_direction,p_transaction_type,p_amount,p_notes,auth.uid()) returning * into t; return t;
end; $$;

create or replace function public.approve_production_order(p_order_id uuid) returns public.production_orders language plpgsql security definer set search_path = public as $$
declare o public.production_orders;
begin
  if auth.uid() is null or not public.current_user_has_permission('production.approve') then raise exception 'غير مصرح باعتماد الإنتاج'; end if;
  update public.production_orders set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_order_id and status='draft' returning * into o;
  if o.id is null then raise exception 'أمر الإنتاج غير قابل للاعتماد'; end if; return o;
end; $$;

-- Existing manager profile is preserved; this id is intentionally not hardcoded into seed data.

-- Preserve existing Supabase Auth users when public data is rebuilt.
insert into public.profiles(id,email,full_name)
select id,email,coalesce(raw_user_meta_data->>'full_name','') from auth.users
on conflict (id) do update set email=excluded.email;
insert into public.user_roles(user_id,role_id)
select p.id,r.id from public.profiles p cross join public.roles r where r.code='manager' and not exists (select 1 from public.user_roles ur where ur.user_id=p.id)
on conflict do nothing;

grant select on public.v_stock_balances, public.v_cash_balances to authenticated;
grant execute on function public.current_user_has_permission(text) to authenticated;
grant execute on function public.current_user_is_manager() to authenticated;
grant execute on function public.stock_balance(uuid,uuid) to authenticated;
grant execute on function public.manager_dashboard_summary() to authenticated;
grant execute on function public.approve_sale(uuid) to authenticated;
grant execute on function public.approve_stock_movement(uuid) to authenticated;
grant execute on function public.approve_expense(uuid) to authenticated;
grant execute on function public.record_cash_transaction(text,uuid,public.movement_direction,text,numeric,text) to authenticated;
grant execute on function public.approve_production_order(uuid) to authenticated;

-- Replacement of the sale approval routine: approval and stock deduction happen in one transaction.
create or replace function public.approve_sale(p_sale_id uuid) returns public.sales language plpgsql security definer set search_path = public as $$
declare s public.sales; m public.stock_movements; item record; balance numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.approve') then raise exception 'غير مصرح باعتماد البيع'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if s.id is null or s.status <> 'draft' then raise exception 'الفاتورة غير قابلة للاعتماد'; end if;
  for item in select * from public.sale_items where sale_id=p_sale_id loop
    balance := public.stock_balance(item.product_id,s.warehouse_id);
    if balance < item.quantity then raise exception 'الرصيد غير كاف للصنف'; end if;
  end loop;
  update public.sales set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_sale_id returning * into s;
  insert into public.stock_movements(document_number,direction,movement_type,warehouse_id,related_sale_id,status,created_by,approved_by,approved_at)
    values ('SALE-'||s.invoice_number,'out','sale',s.warehouse_id,s.id,'approved',auth.uid(),auth.uid(),now()) returning * into m;
  insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_code,unit_cost)
    select m.id,product_id,quantity,unit_code,unit_cost from public.sale_items where sale_id=p_sale_id;
  if s.payment_method='cash' then insert into public.cash_transactions(transaction_number,cash_register_id,direction,transaction_type,amount,related_entity,related_id,created_by) values ('SALE-'||s.invoice_number,s.cash_register_id,'in','sale',s.total,'sales',s.id,auth.uid());
  else insert into public.bank_transactions(transaction_number,bank_id,direction,transaction_type,amount,related_entity,related_id,created_by) values (coalesce(s.bank_transaction_number,'SALE-'||s.invoice_number),s.bank_id,'in','sale',s.total,'sales',s.id,auth.uid()); end if;
  return s;
end; $$;

grant execute on function public.approve_sale(uuid) to authenticated;

create or replace function public.correct_attendance(p_attendance_id uuid,p_check_in_at timestamptz,p_check_out_at timestamptz,p_reason text) returns public.attendance_records language plpgsql security definer set search_path = public as $$
declare a public.attendance_records; updated public.attendance_records;
begin
  if auth.uid() is null or not public.current_user_has_permission('attendance.correct') then raise exception 'غير مصرح بتصحيح الحضور'; end if;
  select * into a from public.attendance_records where id=p_attendance_id for update;
  if a.id is null then raise exception 'سجل الحضور غير موجود'; end if;
  insert into public.attendance_corrections(attendance_id,old_check_in_at,old_check_out_at,new_check_in_at,new_check_out_at,reason,corrected_by) values(a.id,a.check_in_at,a.check_out_at,p_check_in_at,p_check_out_at,p_reason,auth.uid());
  update public.attendance_records set check_in_at=p_check_in_at,check_out_at=p_check_out_at,updated_at=now() where id=a.id returning * into updated; return updated;
end; $$;

grant execute on function public.correct_attendance(uuid,timestamptz,timestamptz,text) to authenticated;
create policy attendance_corrections_read on public.attendance_corrections for select to authenticated using (public.current_user_has_permission('attendance.view'));
create policy attendance_corrections_create on public.attendance_corrections for insert to authenticated with check (public.current_user_has_permission('attendance.correct') and corrected_by=auth.uid());
create policy employee_history_read on public.employee_history for select to authenticated using (public.current_user_has_permission('employees.view'));
create policy employee_history_create on public.employee_history for insert to authenticated with check (public.current_user_has_permission('employees.edit') and changed_by=auth.uid());

create or replace function public.approve_payroll_period(p_period_id uuid) returns public.payroll_periods language plpgsql security definer set search_path = public as $$
declare p public.payroll_periods;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح باعتماد المرتبات'; end if;
  update public.payroll_periods set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_period_id and status='draft' returning * into p;
  if p.id is null then raise exception 'فترة المرتبات غير قابلة للاعتماد'; end if; return p;
end; $$;
grant execute on function public.approve_payroll_period(uuid) to authenticated;

-- Supabase REST access requires SQL grants in addition to RLS policies.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select on public.v_stock_balances, public.v_cash_balances to authenticated;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
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

-- Interactive employee attendance actions.
create or replace function public.toggle_employee_attendance(p_employee_id uuid, p_action text)
returns public.attendance_records
language plpgsql
security definer
set search_path = public
as $$
declare result public.attendance_records; open_record public.attendance_records;
begin
  if auth.uid() is null or not public.current_user_has_permission('attendance.create') then raise exception 'غير مصرح بتسجيل الحضور'; end if;
  if not exists (select 1 from public.employees where id=p_employee_id and status='active') then raise exception 'الموظف غير موجود أو غير نشط'; end if;
  if p_action='check_in' then
    select * into open_record from public.attendance_records where employee_id=p_employee_id and check_out_at is null order by check_in_at desc limit 1;
    if open_record.id is not null then return open_record; end if;
    insert into public.attendance_records(employee_id,status,check_in_at,recorded_by) values(p_employee_id,'present',now(),auth.uid()) returning * into result;
    return result;
  elsif p_action='check_out' then
    update public.attendance_records set check_out_at=now(),updated_at=now() where id=(select id from public.attendance_records where employee_id=p_employee_id and check_out_at is null order by check_in_at desc limit 1) returning * into result;
    if result.id is null then raise exception 'لا يوجد حضور مفتوح لهذا الموظف'; end if;
    return result;
  else raise exception 'الإجراء غير معروف'; end if;
end;
$$;
revoke execute on function public.toggle_employee_attendance(uuid,text) from public;
revoke execute on function public.toggle_employee_attendance(uuid,text) from anon;
grant execute on function public.toggle_employee_attendance(uuid,text) to authenticated;

-- Incentives and automated payroll preparation.
create table if not exists public.employee_incentives (
  id uuid primary key default gen_random_uuid(), batch_number text not null,
  employee_id uuid not null references public.employees(id) on delete restrict,
  title text not null, amount numeric(18,2) not null check (amount > 0), incentive_date date not null default current_date,
  payroll_period_id uuid references public.payroll_periods(id) on delete set null, notes text,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
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
returns setof public.payroll_records language plpgsql security definer set search_path = public as $$
declare period_row public.payroll_periods; e record; r public.payroll_records; basic numeric; bonus numeric; outstanding numeric; advance_part numeric; attended_days numeric; worked_hours numeric;
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
    insert into public.payroll_records(payroll_period_id,employee_id,basic_salary,bonuses,advances_deducted,payment_status) values(p_period_id,e.id,basic,bonus,advance_part,'draft') on conflict(payroll_period_id,employee_id) do update set basic_salary=excluded.basic_salary,bonuses=excluded.bonuses,advances_deducted=excluded.advances_deducted returning * into r;
    update public.employee_incentives set payroll_period_id=p_period_id where employee_id=e.id and incentive_date between period_row.period_start and period_row.period_end and (payroll_period_id is null or payroll_period_id=p_period_id);
    return next r;
  end loop;
end; $$;
revoke execute on function public.prepare_payroll_period(uuid) from public;
revoke execute on function public.prepare_payroll_period(uuid) from anon;
grant execute on function public.prepare_payroll_period(uuid) to authenticated;

-- Incentive batch action: one employee or all active employees.
create or replace function public.grant_employee_incentive(p_batch_number text,p_title text,p_amount numeric,p_scope text,p_employee_id uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare inserted_count integer := 0;
begin
  if auth.uid() is null or not public.current_user_has_permission('payroll.manage') then raise exception 'غير مصرح بإضافة الحوافز'; end if;
  if p_amount <= 0 or length(btrim(p_title)) < 2 then raise exception 'بيانات الحافز غير صحيحة'; end if;
  if p_scope='employee' then
    if p_employee_id is null then raise exception 'اختر الموظف المستحق للحافز'; end if;
    insert into public.employee_incentives(batch_number,employee_id,title,amount,created_by) values(p_batch_number,p_employee_id,p_title,p_amount,auth.uid()); inserted_count := 1;
  elsif p_scope='all' then
    insert into public.employee_incentives(batch_number,employee_id,title,amount,created_by) select p_batch_number,id,p_title,p_amount,auth.uid() from public.employees where status='active'; get diagnostics inserted_count = row_count;
  else raise exception 'نطاق الحافز غير معروف'; end if;
  return inserted_count;
end; $$;
revoke execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) from public;
revoke execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) from anon;
grant execute on function public.grant_employee_incentive(text,text,numeric,text,uuid) to authenticated;

-- Audit coverage for operational and administration tables.
drop trigger if exists audit_attendance_records on public.attendance_records;
create trigger audit_attendance_records after insert or update or delete on public.attendance_records for each row execute function public.write_activity_log();
drop trigger if exists audit_employee_advances on public.employee_advances;
create trigger audit_employee_advances after insert or update or delete on public.employee_advances for each row execute function public.write_activity_log();
drop trigger if exists audit_employee_incentives on public.employee_incentives;
create trigger audit_employee_incentives after insert or update or delete on public.employee_incentives for each row execute function public.write_activity_log();
drop trigger if exists audit_payroll_periods on public.payroll_periods;
create trigger audit_payroll_periods after insert or update or delete on public.payroll_periods for each row execute function public.write_activity_log();
drop trigger if exists audit_payroll_records on public.payroll_records;
create trigger audit_payroll_records after insert or update or delete on public.payroll_records for each row execute function public.write_activity_log();
drop trigger if exists audit_cash_transactions on public.cash_transactions;
create trigger audit_cash_transactions after insert or update or delete on public.cash_transactions for each row execute function public.write_activity_log();
drop trigger if exists audit_bank_transactions on public.bank_transactions;
create trigger audit_bank_transactions after insert or update or delete on public.bank_transactions for each row execute function public.write_activity_log();
drop trigger if exists audit_products on public.products;
create trigger audit_products after insert or update or delete on public.products for each row execute function public.write_activity_log();
drop trigger if exists audit_warehouses on public.warehouses;
create trigger audit_warehouses after insert or update or delete on public.warehouses for each row execute function public.write_activity_log();
drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles after insert or update or delete on public.profiles for each row execute function public.write_activity_log();
drop trigger if exists audit_user_roles on public.user_roles;
create trigger audit_user_roles after insert or update or delete on public.user_roles for each row execute function public.write_activity_log();

-- Atomic point-of-sale draft creation.
create or replace function public.create_sale_draft(p_invoice_number text,p_warehouse_id uuid,p_payment_method public.payment_method,p_cash_register_id uuid,p_bank_id uuid,p_bank_transaction_number text,p_customer_name text,p_discount numeric,p_lines jsonb,p_notes text default null)
returns public.sales language plpgsql security definer set search_path = public as $$
declare s public.sales; customer_id_value uuid; line jsonb; subtotal_value numeric := 0; product_row public.products; quantity_value numeric; price_value numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('sales.create') then raise exception 'غير مصرح بإنشاء الفاتورة'; end if;
  if length(btrim(p_invoice_number)) < 2 or p_warehouse_id is null or jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) < 1 then raise exception 'أكمل رقم الفاتورة والمخزن وصنفًا واحدًا على الأقل'; end if;
  if p_discount < 0 then raise exception 'الخصم غير صحيح'; end if;
  if p_payment_method='cash' and p_cash_register_id is null then raise exception 'اختر الخزنة'; end if;
  if p_payment_method='bank' and (p_bank_id is null or length(btrim(coalesce(p_bank_transaction_number,''))) < 3) then raise exception 'اختر البنك وأدخل رقم العملية البنكية'; end if;
  if p_customer_name is not null and length(btrim(p_customer_name)) > 0 then select id into customer_id_value from public.customers where lower(name)=lower(btrim(p_customer_name)) limit 1; if customer_id_value is null then insert into public.customers(name,created_by) values(btrim(p_customer_name),auth.uid()) returning id into customer_id_value; end if; end if;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into product_row from public.products where id=(line->>'product_id')::uuid and is_active=true for share;
    if product_row.id is null then raise exception 'الصنف المختار غير موجود'; end if;
    quantity_value := (line->>'quantity')::numeric; price_value := coalesce((line->>'unit_price')::numeric,product_row.sale_price);
    if quantity_value <= 0 or price_value < 0 then raise exception 'الكمية أو السعر غير صحيح'; end if;
    subtotal_value := subtotal_value + quantity_value*price_value;
  end loop;
  insert into public.sales(invoice_number,customer_id,warehouse_id,payment_method,cash_register_id,bank_id,bank_transaction_number,subtotal,discount,total,status,notes,created_by) values(p_invoice_number,customer_id_value,p_warehouse_id,p_payment_method,p_cash_register_id,p_bank_id,nullif(btrim(p_bank_transaction_number),''),subtotal_value,p_discount,greatest(0,subtotal_value-p_discount),'draft',p_notes,auth.uid()) returning * into s;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into product_row from public.products where id=(line->>'product_id')::uuid; quantity_value := (line->>'quantity')::numeric; price_value := coalesce((line->>'unit_price')::numeric,product_row.sale_price);
    insert into public.sale_items(sale_id,product_id,quantity,unit_code,unit_price,unit_cost) values(s.id,product_row.id,quantity_value,product_row.unit_code,price_value,product_row.purchase_price);
  end loop;
  return s;
end; $$;
revoke execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) from public;
revoke execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) from anon;
grant execute on function public.create_sale_draft(text,uuid,public.payment_method,uuid,uuid,text,text,numeric,jsonb,text) to authenticated;


-- Migration 010: atomic stock movement draft.
create or replace function public.create_stock_movement_draft(p_document_number text,p_direction public.movement_direction,p_movement_type text,p_warehouse_id uuid,p_product_id uuid,p_quantity numeric,p_unit_code text,p_unit_cost numeric,p_notes text default null)
returns public.stock_movements
language plpgsql
security definer
set search_path = public
as $$
declare m public.stock_movements;
begin
  if auth.uid() is null or not public.current_user_has_permission('inventory.create') then raise exception 'غير مصرح بإنشاء حركة المخزن'; end if;
  if length(btrim(p_document_number)) < 2 or p_warehouse_id is null or p_product_id is null or p_quantity <= 0 then raise exception 'أكمل بيانات الحركة والمخزن والصنف والكمية'; end if;
  insert into public.stock_movements(document_number,direction,movement_type,warehouse_id,movement_date,status,notes,created_by) values(p_document_number,p_direction,p_movement_type,p_warehouse_id,now(),'draft',p_notes,auth.uid()) returning * into m;
  insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_code,unit_cost,notes) values(m.id,p_product_id,p_quantity,p_unit_code,p_unit_cost,p_notes);
  return m;
end;
$$;
revoke execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) from public;
revoke execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) from anon;
grant execute on function public.create_stock_movement_draft(text,public.movement_direction,text,uuid,uuid,numeric,text,numeric,text) to authenticated;


-- Migration 011: manager-only factory operational reset.
create or replace function public.reset_factory_operational_data(p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare reset_at timestamptz := now();
begin
  if auth.uid() is null or not public.current_user_is_manager() then raise exception 'غير مصرح بإعادة ضبط بيانات المصنع'; end if;
  if p_confirmation <> 'إعادة ضبط المصنع' then raise exception 'عبارة التأكيد غير صحيحة'; end if;

  -- Keep auth.users, profiles, user_roles, roles, permissions, role_permissions and units.
  delete from public.payroll_records;
  delete from public.employee_incentives;
  delete from public.payroll_periods;
  delete from public.employee_advances;
  delete from public.attendance_corrections;
  delete from public.attendance_records;
  delete from public.production_outputs;
  delete from public.production_materials;
  delete from public.production_orders;
  delete from public.sale_items;
  delete from public.sales;
  delete from public.stock_movement_lines;
  delete from public.stock_movements;
  delete from public.expenses;
  delete from public.cash_transactions;
  delete from public.bank_transactions;
  delete from public.customers;
  delete from public.employees;
  delete from public.products;
  delete from public.warehouses;
  delete from public.cash_registers;
  delete from public.banks;
  delete from public.shifts;
  delete from public.departments;
  delete from public.job_titles;
  delete from public.product_categories;
  delete from public.expense_categories;

  insert into public.activity_logs(actor_id,action,entity_type,reason,severity,created_at)
  values(auth.uid(),'RESET_FACTORY','factory','إعادة ضبط بيانات التشغيل بطلب المدير','critical',reset_at);
  return jsonb_build_object('ok',true,'reset_at',reset_at);
end;
$$;
revoke execute on function public.reset_factory_operational_data(text) from public;
revoke execute on function public.reset_factory_operational_data(text) from anon;
grant execute on function public.reset_factory_operational_data(text) to authenticated;


-- Migration 012: include employee history in operational reset.
create or replace function public.reset_factory_operational_data(p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare reset_at timestamptz := now();
begin
  if auth.uid() is null or not public.current_user_is_manager() then raise exception 'غير مصرح بإعادة ضبط بيانات المصنع'; end if;
  if p_confirmation <> 'إعادة ضبط المصنع' then raise exception 'عبارة التأكيد غير صحيحة'; end if;

  delete from public.payroll_records;
  delete from public.employee_incentives;
  delete from public.payroll_periods;
  delete from public.employee_advances;
  delete from public.attendance_corrections;
  delete from public.attendance_records;
  delete from public.production_outputs;
  delete from public.production_materials;
  delete from public.production_orders;
  delete from public.sale_items;
  delete from public.sales;
  delete from public.stock_movement_lines;
  delete from public.stock_movements;
  delete from public.expenses;
  delete from public.cash_transactions;
  delete from public.bank_transactions;
  delete from public.customers;
  delete from public.employee_history;
  delete from public.employees;
  delete from public.products;
  delete from public.warehouses;
  delete from public.cash_registers;
  delete from public.banks;
  delete from public.shifts;
  delete from public.departments;
  delete from public.job_titles;
  delete from public.product_categories;
  delete from public.expense_categories;

  insert into public.activity_logs(actor_id,action,entity_type,reason,severity,created_at)
  values(auth.uid(),'RESET_FACTORY','factory','إعادة ضبط بيانات التشغيل بطلب المدير','critical',reset_at);
  return jsonb_build_object('ok',true,'reset_at',reset_at);
end;
$$;
revoke execute on function public.reset_factory_operational_data(text) from public;
revoke execute on function public.reset_factory_operational_data(text) from anon;
grant execute on function public.reset_factory_operational_data(text) to authenticated;


-- Migration 013: remove unsafe admin-service triggers.
-- Profiles and user_roles are maintained by the admin Edge Function with service-role context.
-- They do not use the generic row-id audit trigger safely, so keep their changes out of this trigger.
drop trigger if exists audit_profiles on public.profiles;
drop trigger if exists audit_user_roles on public.user_roles;
