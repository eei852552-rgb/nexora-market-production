-- QA PROJECT ONLY. Never apply this script to production.
-- Target: the separate Supabase project named nexora-market-qa.
-- This changes current table privileges only; it does not modify rows,
-- RLS policies, functions, triggers, or production resources.
-- Review the project ref and table list before running as the QA database owner.

begin;

revoke all privileges on table
  public.admin_roles,
  public.advertisements,
  public.carts,
  public.order_items,
  public.orders,
  public.products,
  public.profiles,
  public.seller_applications,
  public.wishlists
from public, anon, authenticated;

-- Match the production role model, with COD order tables tightened to SELECT-only.
grant select on table public.admin_roles to authenticated;
grant select on table public.advertisements to anon, authenticated;
grant insert, update, delete on table public.advertisements to authenticated;
grant select, insert, update, delete on table public.carts to authenticated;
grant select on table public.order_items, public.orders to authenticated;
grant select on table public.products to anon, authenticated;
grant insert, update, delete on table public.products to authenticated;
grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.seller_applications to authenticated;
grant select, insert, update, delete on table public.wishlists to authenticated;

-- Default privileges are intentionally unchanged here. The connected hosted
-- SQL role cannot alter defaults owned by supabase_admin. Current tables are
-- hardened below; future tables require a separate owner-level default-ACL change.

do $acl$
declare
  t text;
begin
  foreach t in array array[
    'public.admin_roles','public.advertisements','public.carts',
    'public.order_items','public.orders','public.products',
    'public.profiles','public.seller_applications','public.wishlists'
  ] loop
    if has_table_privilege('anon', t, 'TRUNCATE')
       or has_table_privilege('authenticated', t, 'TRUNCATE')
       or has_table_privilege('anon', t, 'REFERENCES')
       or has_table_privilege('authenticated', t, 'REFERENCES')
       or has_table_privilege('anon', t, 'TRIGGER')
       or has_table_privilege('authenticated', t, 'TRIGGER') then
      raise exception 'unsafe table privilege remains on %', t;
    end if;
  end loop;

  if not has_table_privilege('authenticated','public.orders','SELECT')
     or not has_table_privilege('authenticated','public.order_items','SELECT')
     or not has_table_privilege('authenticated','public.carts','INSERT')
     or not has_table_privilege('anon','public.products','SELECT')
     or not has_table_privilege('anon','public.advertisements','SELECT') then
    raise exception 'required application grants are missing';
  end if;

  if has_table_privilege('anon','public.orders','SELECT')
     or has_table_privilege('anon','public.order_items','SELECT')
     or has_table_privilege('anon','public.carts','SELECT')
     or has_table_privilege('authenticated','public.orders','INSERT')
     or has_table_privilege('authenticated','public.order_items','INSERT') then
    raise exception 'COD table grants are not least privilege';
  end if;
end
$acl$;

commit;
