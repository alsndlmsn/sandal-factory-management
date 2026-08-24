-- Profiles and user_roles are maintained by the admin Edge Function with service-role context.
-- They do not use the generic row-id audit trigger safely, so keep their changes out of this trigger.
drop trigger if exists audit_profiles on public.profiles;
drop trigger if exists audit_user_roles on public.user_roles;
