-- تحسين توزيع الحسابات في قيود المشتريات والمرتبات.
create or replace function public.post_purchase_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare cash_total numeric:=0; bank_total numeric:=0; payable numeric:=0; raw_gross numeric:=0; product_gross numeric:=0; gross_total numeric:=0; factor numeric:=1; raw_total numeric:=0; product_total numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(case when raw_material_id is not null then total else 0 end),0),coalesce(sum(case when product_id is not null then total else 0 end),0) into raw_gross,product_gross from public.purchase_items where purchase_id=new.id;
    gross_total:=raw_gross+product_gross; factor:=case when gross_total>0 then greatest(1-greatest(coalesce(new.discount,0),0)/gross_total,0) else 1 end; raw_total:=raw_gross*factor; product_total:=product_gross*factor;
    cash_total:=case when new.payment_method='cash' then greatest(coalesce(new.paid_amount,0),0) else 0 end; bank_total:=case when new.payment_method='bank' then greatest(coalesce(new.paid_amount,0),0) else 0 end; payable:=greatest(coalesce(new.total,0)-cash_total-bank_total,0);
    if raw_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1210','debit',raw_total,'credit',0,'description','إضافة مخزون مواد خام')); end if;
    if product_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1200','debit',product_total,'credit',0,'description','إضافة مخزون منتجات مشتراة')); end if;
    if cash_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1000','debit',0,'credit',cash_total,'description','سداد شراء نقدي')); end if;
    if bank_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1010','debit',0,'credit',bank_total,'description','سداد شراء بنكي')); end if;
    if payable>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2000','debit',0,'credit',payable,'description','رصيد مستحق للمورد')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('purchase',new.id,new.purchase_at::date,'قيد شراء '||new.purchase_number,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_payroll_accrual_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare wages numeric:=0; incentives numeric:=0; advance numeric:=0; payable numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(base_amount-deductions),0),coalesce(sum(incentives),0),coalesce(sum(advance_deduction),0) into wages,incentives,advance from public.payroll_records where period_id=new.id;
    payable:=greatest(wages+incentives-advance,0);
    if wages>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6100','debit',wages,'credit',0,'description','أجور أساسية مستحقة')); end if;
    if incentives>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6200','debit',incentives,'credit',0,'description','حوافز مستحقة')); end if;
    if payable>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2100','debit',0,'credit',payable,'description','رواتب مستحقة')); end if;
    if advance>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1300','debit',0,'credit',advance,'description','تسوية سلف العاملين')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('payroll_period',new.id,new.to_date,'استحقاق مرتبات '||new.period_name,new.created_by,lines); end if;
  end if; return new;
end; $$;

create or replace function public.post_return_journal() returns trigger language plpgsql security definer set search_path=public as $$
declare cash_total numeric:=0; bank_total numeric:=0; ar_total numeric:=0; net_return numeric:=0; vat numeric:=0; returned_cost numeric:=0; damaged_cost numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(case when sp.cash_register_id is not null then rr.amount else 0 end),0),coalesce(sum(case when sp.bank_id is not null then rr.amount else 0 end),0) into cash_total,bank_total from public.return_refunds rr join public.sale_payments sp on sp.id=rr.sale_payment_id where rr.return_id=new.id;
    net_return:=greatest(coalesce(new.total,0)-coalesce(new.vat_amount,0),0); vat:=greatest(coalesce(new.vat_amount,0),0); ar_total:=greatest(coalesce(new.total,0)-cash_total-bank_total,0);
    select coalesce(sum((ri.good_quantity+ri.inspection_quantity)*si.cost_price),0),coalesce(sum(ri.damaged_quantity*si.cost_price),0) into returned_cost,damaged_cost from public.return_items ri join public.sale_items si on si.id=ri.sale_item_id where ri.return_id=new.id;
    if net_return>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','4000','debit',net_return,'credit',0,'description','عكس إيراد مرتجع')); end if;
    if vat>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2200','debit',vat,'credit',0,'description','عكس ضريبة مبيعات')); end if;
    if cash_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1000','debit',0,'credit',cash_total,'description','رد نقدي')); end if;
    if bank_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1010','debit',0,'credit',bank_total,'description','رد بنكي')); end if;
    if ar_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1100','debit',0,'credit',ar_total,'description','عكس ذمة العميل')); end if;
    if returned_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1220','debit',returned_cost,'credit',0,'description','عودة مخزون منتج تام')); end if;
    if damaged_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6300','debit',damaged_cost,'credit',0,'description','تكلفة تالف مرتجع')); end if;
    if returned_cost+damaged_cost>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','5000','debit',0,'credit',returned_cost+damaged_cost,'description','عكس تكلفة البضاعة')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('return',new.id,new.return_at::date,'قيد مرتجع '||new.return_number,new.created_by,lines); end if;
  end if; return new;
end; $$;
