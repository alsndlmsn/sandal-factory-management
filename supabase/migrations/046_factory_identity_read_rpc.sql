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
        'vatRate', value->>'vatRate'
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
