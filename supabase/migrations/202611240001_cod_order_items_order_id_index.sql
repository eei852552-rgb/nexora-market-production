-- Add the child-side index for the COD order_items -> orders foreign key.
-- This keeps order detail reads and parent-row FK checks efficient.
-- Safe additive DDL: no row changes and no production deployment implied.

create index if not exists order_items_order_id_idx
  on public.order_items (order_id);
