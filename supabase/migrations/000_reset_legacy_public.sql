-- DESTRUCTIVE MIGRATION — run only after explicit confirmation and backup review.
-- This resets application tables, views, functions and policies in public.
-- It does NOT drop auth.users, Supabase Auth sessions, or storage objects.
drop schema if exists public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
alter default privileges in schema public grant all on tables to postgres, service_role;
alter default privileges in schema public grant all on functions to postgres, service_role;
alter default privileges in schema public grant all on sequences to postgres, service_role;
