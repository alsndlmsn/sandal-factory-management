-- إصلاح تعارض متغير incentives مع عمود payroll_records.incentives.
create or replace function public.post_payroll_accrual_journal()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  wages numeric:=0; v_incentives numeric:=0; advance numeric:=0; payable numeric:=0; lines jsonb:='[]'::jsonb;
begin
  if new.status='approved' and (old.status is distinct from new.status) then
    select coalesce(sum(pr.base_amount-pr.deductions),0),coalesce(sum(pr.incentives),0),coalesce(sum(pr.advance_deduction),0)
    into wages,v_incentives,advance
    from public.payroll_records pr where pr.period_id=new.id;
    payable:=greatest(wages+v_incentives-advance,0);
    if wages>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6100','debit',wages,'credit',0,'description','أجور أساسية مستحقة')); end if;
    if v_incentives>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','6200','debit',v_incentives,'credit',0,'description','حوافز مستحقة')); end if;
    if payable>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2100','debit',0,'credit',payable,'description','رواتب مستحقة')); end if;
    if advance>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1300','debit',0,'credit',advance,'description','تسوية سلف العاملين')); end if;
    if jsonb_array_length(lines)>=2 then perform public.post_journal('payroll_period',new.id,new.to_date,'استحقاق مرتبات '||new.period_name,new.created_by,lines); end if;
  end if; return new;
end; $$;

grant execute on function public.post_payroll_accrual_journal() to authenticated;
revoke execute on function public.post_payroll_accrual_journal() from anon;
