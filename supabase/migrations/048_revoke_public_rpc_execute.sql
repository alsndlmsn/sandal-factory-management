-- منع دور PUBLIC/anon من استدعاء دوال الهوية والوصول والإعدادات.
-- تبقى الدوال متاحة للحسابات المسجلة، وتستمر حواجز الصلاحيات الداخلية.
revoke execute on function public.get_current_user_access() from public;
grant execute on function public.get_current_user_access() to authenticated;

revoke execute on function public.get_factory_identity() from public;
grant execute on function public.get_factory_identity() to authenticated;

revoke execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text) from public;
grant execute on function public.save_factory_settings(text,text,numeric,text,text,text,text,text) to authenticated;
