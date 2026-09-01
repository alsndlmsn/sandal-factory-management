-- توحيد صلاحيات الموردين ومدفوعات الموردين مع صلاحية المشتريات المستخدمة في الواجهة.
-- لا يمنح صلاحية جديدة؛ بل يصلح سياسة RLS لتطابق purchases.view الموجودة فعليًا.
drop policy if exists suppliers_view on public.suppliers;
create policy suppliers_view on public.suppliers
for select to authenticated
using (public.current_user_is_manager() or public.current_user_has_permission('purchases.view'));

drop policy if exists supplier_payments_view on public.supplier_payments;
create policy supplier_payments_view on public.supplier_payments
for select to authenticated
using (public.current_user_is_manager() or public.current_user_has_permission('purchases.view'));
