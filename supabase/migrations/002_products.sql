create or replace function public.create_product(
  p_name text,
  p_category text default null,
  p_unit text default null,
  p_cost_price numeric default 0,
  p_sale_price numeric default 0,
  p_minimum_stock numeric default 0,
  p_notes text default null,
  p_custom_fields jsonb default '{}'::jsonb
) returns public.products
language plpgsql security definer set search_path=public as $$
declare p public.products; cid uuid; uid uuid;
begin
  if auth.uid() is null or not public.current_user_has_permission('products.create') then raise exception 'غير مصرح بإضافة منتج'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'اسم المنتج مطلوب'; end if;
  if p_category is not null and nullif(btrim(p_category),'') is not null then
    insert into public.product_categories(name,created_by) values(btrim(p_category),auth.uid()) on conflict(name) do update set name=excluded.name returning id into cid;
  end if;
  if p_unit is not null and nullif(btrim(p_unit),'') is not null then
    insert into public.units(name,created_by) values(btrim(p_unit),auth.uid()) on conflict(name) do update set name=excluded.name returning id into uid;
  end if;
  insert into public.products(name,category_id,category_name,unit_id,unit_name,cost_price,sale_price,minimum_stock,notes,custom_fields,created_by)
  values(btrim(p_name),cid,nullif(btrim(p_category),''),uid,nullif(btrim(p_unit),''),greatest(p_cost_price,0),greatest(p_sale_price,0),greatest(p_minimum_stock,0),p_notes,coalesce(p_custom_fields,'{}'::jsonb),auth.uid()) returning * into p;
  return p;
end; $$;
create or replace function public.update_product(
  p_id uuid,p_name text,p_category text default null,p_unit text default null,p_cost_price numeric default 0,p_sale_price numeric default 0,p_minimum_stock numeric default 0,p_notes text default null,p_custom_fields jsonb default '{}'::jsonb
) returns public.products
language plpgsql security definer set search_path=public as $$
declare p public.products; cid uuid; uid uuid;
begin
  if auth.uid() is null or not public.current_user_has_permission('products.edit') then raise exception 'غير مصرح بتعديل المنتج'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'اسم المنتج مطلوب'; end if;
  if p_category is not null and nullif(btrim(p_category),'') is not null then insert into public.product_categories(name,created_by) values(btrim(p_category),auth.uid()) on conflict(name) do update set name=excluded.name returning id into cid; end if;
  if p_unit is not null and nullif(btrim(p_unit),'') is not null then insert into public.units(name,created_by) values(btrim(p_unit),auth.uid()) on conflict(name) do update set name=excluded.name returning id into uid; end if;
  update public.products set name=btrim(p_name),category_id=cid,category_name=nullif(btrim(p_category),''),unit_id=uid,unit_name=nullif(btrim(p_unit),''),cost_price=greatest(p_cost_price,0),sale_price=greatest(p_sale_price,0),minimum_stock=greatest(p_minimum_stock,0),notes=p_notes,custom_fields=coalesce(p_custom_fields,'{}'::jsonb),updated_at=now() where id=p_id returning * into p;
  if p.id is null then raise exception 'المنتج غير موجود'; end if; return p;
end; $$;
create or replace function public.toggle_product(p_id uuid,p_active boolean) returns public.products
language plpgsql security definer set search_path=public as $$
declare p public.products;
begin
  if auth.uid() is null or not public.current_user_has_permission('products.edit') then raise exception 'غير مصرح بتغيير حالة المنتج'; end if;
  update public.products set is_active=p_active,updated_at=now() where id=p_id returning * into p;
  if p.id is null then raise exception 'المنتج غير موجود'; end if; return p;
end; $$;
revoke all on function public.create_product(text,text,text,numeric,numeric,numeric,text,jsonb) from public;
revoke all on function public.update_product(uuid,text,text,text,numeric,numeric,numeric,text,jsonb) from public;
revoke all on function public.toggle_product(uuid,boolean) from public;
grant execute on function public.create_product(text,text,text,numeric,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.update_product(uuid,text,text,text,numeric,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.toggle_product(uuid,boolean) to authenticated;
