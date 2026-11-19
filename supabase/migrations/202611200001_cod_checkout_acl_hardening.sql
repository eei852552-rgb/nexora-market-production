-- Least-privilege grants for COD tables.
-- RLS does not protect tables from TRUNCATE, REFERENCES, or TRIGGER privileges.
-- Apply after 202611190001_cod_checkout_idempotency.sql.
-- Safe to re-run; does not modify or delete application rows.

begin;

revoke all privileges on table
  public.orders,
  public.order_items,
  public.carts,
  public.products
from public, anon, authenticated;

-- Buyers and sellers read orders/items through the existing RLS policies only.
grant select on table public.orders, public.order_items to authenticated;

-- The cart UI needs owner-scoped CRUD; it must not have TRUNCATE or DDL-like grants.
grant select, insert, update, delete on table public.carts to authenticated;

-- Catalog is public-read; signed-in sellers use the existing RLS policies for CRUD.
grant select on table public.products to anon, authenticated;
grant insert, update, delete on table public.products to authenticated;

commit;
