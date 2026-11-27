-- QA project only: harden future public objects created by postgres.
-- This does not change existing tables, sequences, functions, or application rows.
-- The supabase_admin-owned defaults require a separate owner-authorized change.

begin;

alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

do $verify$
declare
  v_owner oid := 'postgres'::regrole;
  v_anon oid := 'anon'::regrole;
  v_authenticated oid := 'authenticated'::regrole;
begin
  if exists (
    select 1
    from pg_default_acl d
    cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole = v_owner
      and d.defaclnamespace = 'public'::regnamespace
      and d.defaclobjtype in ('r','S','f')
      and a.grantee in (0, v_anon, v_authenticated)
  ) then
    raise exception 'unsafe postgres-owned public schema defaults remain';
  end if;
end
$verify$;

commit;
