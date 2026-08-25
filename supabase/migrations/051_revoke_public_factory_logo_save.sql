-- سحب التنفيذ العام صراحةً من دالة حفظ إعدادات المصنع.
revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) from public;
revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) from anon;
grant execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) to authenticated;
