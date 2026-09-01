-- إزالة اسم السياسة القديم الذي كان يعتمد suppliers.view غير الممنوحة.
-- السياسة البديلة supplier_payments_view في migration 056 تعتمد purchases.view.
drop policy if exists finance_payments_view on public.supplier_payments;
