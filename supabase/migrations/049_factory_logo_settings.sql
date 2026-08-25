-- إضافة رابط شعار المصنع إلى إعدادات الهوية، مع حصر التعديل في المدير.
create or replace function public.get_factory_identity()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'factoryName', value->>'factoryName',
        'factoryNumber', value->>'factoryNumber',
        'address', value->>'address',
        'phone', value->>'phone',
        'email', value->>'email',
        'invoiceFooter', value->>'invoiceFooter',
        'currency', value->>'currency',
        'vatRate', value->>'vatRate',
        'factoryLogo', value->>'factoryLogo'
      )
      from public.settings
      where key='factory'
      limit 1
    ),
    '{}'::jsonb
  );
$$;

grant execute on function public.get_factory_identity() to authenticated;
revoke execute on function public.get_factory_identity() from anon;

create or replace function public.save_factory_settings(
  p_factory_name text,
  p_currency text,
  p_vat_rate numeric default 0,
  p_factory_number text default null,
  p_address text default null,
  p_phone text default null,
  p_email text default null,
  p_invoice_footer text default null,
  p_factory_logo text default null
) returns public.settings
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.settings;
  mgr boolean;
  logo text := nullif(btrim(p_factory_logo), '');
begin
  select coalesce(is_manager,false) into mgr
  from public.profiles
  where id=auth.uid();

  if auth.uid() is null or not coalesce(mgr,false) then
    raise exception 'إعدادات المصنع متاحة للمدير فقط';
  end if;
  if nullif(btrim(p_factory_name),'') is null then
    raise exception 'اسم المصنع مطلوب';
  end if;
  if p_vat_rate < 0 or p_vat_rate > 100 then
    raise exception 'نسبة الضريبة يجب أن تكون بين صفر و100';
  end if;
  if logo is not null and (length(logo) > 2048 or logo !~* '^(https?://|/|\./|\.\./)') then
    raise exception 'رابط الشعار يجب أن يكون مسارًا محليًا أو رابط http/https صالحًا';
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
      'invoiceFooter', coalesce(nullif(btrim(p_invoice_footer),''),'شكرًا لتعاملكم معنا.'),
      'factoryLogo', logo
    ),
    auth.uid(), now()
  )
  on conflict(key) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now()
  returning * into s;
  return s;
end;
$$;

grant execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) to authenticated;
revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) from anon;
