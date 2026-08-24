create or replace function public.approve_return(p_return_id uuid) returns public.returns language plpgsql security definer set search_path=public as $$
declare r public.returns; item record; sale public.sales; mov public.stock_movements; damaged public.damaged_goods;
begin
 if auth.uid() is null or not public.current_user_has_permission('returns.approve') then raise exception 'غير مصرح باعتماد المرتجع'; end if;
 select * into r from public.returns where id=p_return_id for update;
 if r.id is null then raise exception 'المرتجع غير موجود'; end if;
 if r.status<>'draft' then raise exception 'المرتجع اعتمد أو ألغي سابقًا'; end if;
 select * into sale from public.sales where id=r.sale_id for update;
 if sale.id is null or sale.status<>'approved' then raise exception 'الفاتورة الأصلية غير معتمدة'; end if;
 insert into public.stock_movements(direction,source_type,source_id,to_warehouse_id,status,created_by,approved_by,approved_at,notes) values('in','return',r.id,sale.warehouse_id,'approved',auth.uid(),auth.uid(),now(),'إرجاع صالح من '||r.return_number) returning * into mov;
 for item in select * from public.return_items where return_id=r.id loop
   if coalesce(item.good_quantity,0)>0 then insert into public.stock_movement_lines(movement_id,product_id,quantity,unit_name,cost_price,notes) select mov.id,item.product_id,item.good_quantity,p.unit_name,p.cost_price,'مرتجع صالح '||r.return_number from public.products p where p.id=item.product_id; end if;
   if coalesce(item.damaged_quantity,0)>0 then insert into public.damaged_goods(product_id,quantity,unit_name,source_type,source_id,reason,status,notes,created_by) select item.product_id,item.damaged_quantity,p.unit_name,'return',r.id,'تالف من مرتجع','pending','مرتجع '||r.return_number,auth.uid() from public.products p where p.id=item.product_id; end if;
 end loop;
 if r.total>0 and sale.paid_amount>0 then
   if sale.payment_method='cash' and sale.cash_register_id is not null then insert into public.cash_transactions(cash_register_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(sale.cash_register_id,'out','refund',least(r.total,sale.paid_amount),'return',r.id,auth.uid(),'رد قيمة '||r.return_number); end if;
   if sale.payment_method='bank' and sale.bank_id is not null then insert into public.bank_transactions(bank_id,direction,transaction_type,amount,related_type,related_id,created_by,notes) values(sale.bank_id,'out','refund',least(r.total,sale.paid_amount),'return',r.id,auth.uid(),'رد قيمة '||r.return_number); end if;
 end if;
 update public.returns set status='approved',approved_by=auth.uid(),approved_at=now() where id=r.id returning * into r;
 return r;
end; $$;
insert into public.permissions(code,name_ar,module) values('returns.approve','اعتماد مرتجع','returns') on conflict(code) do nothing;
grant execute on function public.approve_return(uuid) to authenticated;
grant select,insert,update on public.damaged_goods,public.return_items,public.returns to authenticated;
