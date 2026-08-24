-- إصلاح تعارض اسم المتغير si مع alias الجدول، واستبعاد remaining_amount المولّد.
create or replace function public.approve_return(p_return_id uuid)
returns public.returns
language plpgsql security definer set search_path=public as $$
declare
  r public.returns; item record; sale public.sales; v_sale_item public.sale_items; mov public.stock_movements; paid_left numeric; refund_left numeric; refund_part numeric; pay record; returned_before numeric;
begin
  if auth.uid() is null or not public.current_user_has_permission('returns.approve') then raise exception 'غير مصرح باعتماد المرتجع'; end if;
  select * into r from public.returns where id=p_return_id for update;
  if r.id is null then raise exception 'المرتجع غير موجود'; end if;
  if r.status<>'draft' then raise exception 'المرتجع اعتمد أو ألغي سابقًا'; end if;
  select * into sale from public.sales where id=r.sale_id for update;
  if sale.id is null or sale.status<>'approved' then raise exception 'الفاتورة الأصلية غير معتمدة'; end if;
  for item in
    select ri.*,sale_line.quantity as sold_quantity
    from public.return_items ri
    join public.sale_items sale_line on sale_line.id=ri.sale_item_id
    where ri.return_id=r.id
  loop
    select coalesce(sum(ri2.quantity),0) into returned_before
    from public.return_items ri2
    join public.returns rr on rr.id=ri2.return_id
    where ri2.sale_item_id=item.sale_item_id and rr.status='approved' and rr.id<>r.id;
    if item.quantity<=0 or item.quantity+returned_before>item.sold_quantity then raise exception 'كمية المرتجع تتجاوز الكمية المتاحة في الفاتورة'; end if;
    if coalesce(item.good_quantity,0)+coalesce(item.damaged_quantity,0)+coalesce(item.inspection_quantity,0)<>item.quantity then raise exception 'تقسيم المرتجع لا يساوي الكمية'; end if;
  end loop;
  if exists(select 1 from public.return_items where return_id=r.id and good_quantity>0) then
    insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at,notes)
    values('in','return',r.id,sale.warehouse_id,'approved',auth.uid(),auth.uid(),now(),'إرجاع صالح من '||r.return_number) returning * into mov;
    insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_name,cost_price,notes)
    select mov.id,ri.product_id,ri.good_quantity,p.unit_name,p.cost_price,'مرتجع صالح '||r.return_number
    from public.return_items ri join public.products p on p.id=ri.product_id
    where ri.return_id=r.id and ri.good_quantity>0;
  end if;
  insert into public.damaged_goods(product_id,quantity,unit_name,source_type,source_id,reason,status,notes,created_by)
  select ri.product_id,ri.damaged_quantity,p.unit_name,'return',r.id,'تالف من مرتجع','pending','مرتجع '||r.return_number,auth.uid()
  from public.return_items ri join public.products p on p.id=ri.product_id
  where ri.return_id=r.id and ri.damaged_quantity>0;
  refund_left:=least(greatest(coalesce(r.total,0),0),greatest(coalesce(sale.paid_amount,0),0));
  for pay in select sp.* from public.sale_payments sp where sp.sale_id=sale.id and sp.amount>0 order by sp.paid_at,sp.id for update loop
    exit when refund_left<=0;
    paid_left:=pay.amount-coalesce((select sum(rr.amount) from public.return_refunds rr where rr.sale_payment_id=pay.id),0);
    refund_part:=least(greatest(paid_left,0),refund_left);
    if refund_part>0 then
      insert into public.return_refunds(return_id,sale_payment_id,amount) values(r.id,pay.id,refund_part);
      if pay.cash_register_id is not null then
        insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(pay.cash_register_id,'out','refund',refund_part,'return',r.id,auth.uid(),'رد قيمة '||r.return_number);
      elsif pay.bank_id is not null then
        insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(pay.bank_id,'out','refund',refund_part,'return',r.id,auth.uid(),'رد قيمة '||r.return_number);
      end if;
      refund_left:=refund_left-refund_part;
    end if;
  end loop;
  update public.sales
  set paid_amount=greatest(coalesce(paid_amount,0)-greatest(coalesce(r.total,0)-refund_left,0),0)
  where id=sale.id;
  update public.returns set status='approved',approved_by=auth.uid(),approved_at=now() where id=r.id returning * into r;
  return r;
end; $$;

grant execute on function public.approve_return(uuid) to authenticated;
revoke execute on function public.approve_return(uuid) from anon;
