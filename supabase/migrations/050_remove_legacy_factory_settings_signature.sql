-- إزالة التوقيع القديم حتى لا يبقى مسار حفظ يتجاهل الشعار.
drop function if exists public.save_factory_settings(text,text,numeric,text,text,text,text,text);

grant execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) to authenticated;
revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text,text) from anon;
