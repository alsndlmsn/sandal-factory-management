drop function if exists public.save_factory_settings(text,text,numeric);

create or replace function public.save_factory_settings(
  p_factory_name text,
  p_currency text,
  p_vat_rate numeric default 0,
  p_factory_number text default null,
  p_address text default null,
  p_phone text default null,
  p_email text default null,
  p_invoice_footer text default null
) returns public.settings
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.settings;
  mgr boolean;
begin
  select coalesce(is_manager,false) into mgr from public.profiles where id=auth.uid();
  if auth.uid() is null or not coalesce(mgr,false) then
    raise exception 'إعدادات المصنع متاحة للمدير فقط';
  end if;
  if nullif(btrim(p_factory_name),'') is null then
    raise exception 'اسم المصنع مطلوب';
  end if;
  if p_vat_rate < 0 or p_vat_rate > 100 then
    raise exception 'نسبة الضريبة يجب أن تكون بين صفر و100';
  end if;
  insert into public.settings(key,value,updated_by,updated_at)
  values(
    'factory',
    jsonb_build_object(
      'factoryName', btrim(p_factory_name),
      'currency', coalesce(nullif(btrim(p_currency),''),'ج.س'),
      'vatRate', coalesce(p_vat_rate,0),
      'factoryNumber', nullif(btrim(p_factory_number),''),
      'address', nullif(btrim(p_address),''),
      'phone', nullif(btrim(p_phone),''),
      'email', nullif(btrim(p_email),''),
      'invoiceFooter', coalesce(nullif(btrim(p_invoice_footer),''),'شكرًا لتعاملكم معنا.')
    ),
    auth.uid(), now()
  )
  on conflict(key) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now()
  returning * into s;
  return s;
end;
$$;

grant execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text) to authenticated;
revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text) from anon;
