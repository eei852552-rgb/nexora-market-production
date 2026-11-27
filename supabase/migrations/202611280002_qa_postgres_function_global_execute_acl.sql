-- QA project only: remove PostgreSQL's global default PUBLIC EXECUTE on
-- functions created by postgres. A schema-local REVOKE cannot remove this
-- inherited global default. Existing functions are not changed.
-- The supabase_admin-owned defaults require a separate owner-authorized change.

begin;

alter default privileges for role postgres
  revoke execute on functions from public;

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
      and d.defaclnamespace = 0
      and d.defaclobjtype = 'f'
      and a.grantee = 0
  ) then
    raise exception 'global PUBLIC EXECUTE default remains for postgres-owned functions';
  end if;

  if exists (
    select 1
    from pg_default_acl d
    cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole = v_owner
      and d.defaclnamespace = 'public'::regnamespace
      and d.defaclobjtype in ('S','f')
      and a.grantee in (0, v_anon, v_authenticated)
  ) then
    raise exception 'unsafe postgres-owned public sequence/function defaults remain';
  end if;
end
$verify$;

commit;
