-- Retry-safe COD checkout and cart snapshot cleanup.
-- Apply only to an isolated QA database after reviewing the current schema.
-- This migration is NOT applied to the live Supabase project.

alter table public.orders
  add column if not exists request_id uuid;

create unique index if not exists orders_buyer_request_id_uidx
  on public.orders (buyer_id, request_id)
  where request_id is not null;

-- Remove browser-side order creation. Checkout must use the guarded RPC only.
drop policy if exists orders_buyer_insert on public.orders;
drop policy if exists order_items_buyer_insert on public.order_items;
revoke insert on public.orders, public.order_items from anon, authenticated;

-- PostgREST does not support overloaded function names. Replace the old 3-arg RPC.
revoke all on function public.create_cod_order(text, text, text) from public, anon, authenticated;
drop function public.create_cod_order(text, text, text);

-- Keep the privileged implementation in a non-exposed schema.
create schema if not exists private;
grant usage on schema private to authenticated;

-- Avoid mutually recursive RLS policies between orders and order_items.
-- These narrowly scoped helpers run as the migration owner and use auth.uid()
-- to answer one ownership/participation question without exposing row data.
create or replace function private.is_order_seller(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.seller_id = auth.uid()
  );
$;

create or replace function private.is_order_buyer(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and o.buyer_id = auth.uid()
  );
$;

revoke all on function private.is_order_seller(uuid) from public, anon;
revoke all on function private.is_order_buyer(uuid) from public, anon;
grant execute on function private.is_order_seller(uuid) to authenticated;
grant execute on function private.is_order_buyer(uuid) to authenticated;

drop policy if exists sellers_can_view_relevant_orders on public.orders;
create policy sellers_can_view_relevant_orders
  on public.orders for select to authenticated
  using (private.is_order_seller(id));

drop policy if exists order_items_participant_read on public.order_items;
create policy order_items_participant_read
  on public.order_items for select to authenticated
  using (
    seller_id = (select auth.uid())
    or private.is_order_buyer(order_id)
  );

create or replace function private.create_cod_order_impl(
  p_delivery_name text,
  p_delivery_phone text,
  p_delivery_address text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_total numeric;
  v_status text;
  v_cart_snapshot jsonb;
  v_cart_count integer;
  v_processed_count integer := 0;
  v_deleted_count integer;
  v_item record;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  if p_request_id is null then
    raise exception 'checkout request ID is required';
  end if;

  if char_length(trim(coalesce(p_delivery_name, ''))) < 2
     or char_length(trim(coalesce(p_delivery_phone, ''))) < 6
     or char_length(trim(coalesce(p_delivery_address, ''))) < 8 then
    raise exception 'delivery details are incomplete';
  end if;

  -- Idempotent replay: return the original order for this buyer/request pair.
  select o.id, o.total, o.status::text
    into v_order_id, v_total, v_status
  from public.orders o
  where o.buyer_id = v_user and o.request_id = p_request_id;

  if found then
    return jsonb_build_object(
      'order_id', v_order_id,
      'total', v_total,
      'currency', 'MMK',
      'status', v_status,
      'payment_method', 'cod',
      'idempotent_replay', true
    );
  end if;

  -- Lock and snapshot cart rows in one statement. This prevents a new cart
  -- row committed between a separate lock statement and snapshot statement
  -- from being accidentally consumed by this checkout.
  with locked_cart as materialized (
    select c.product_id, c.quantity, c.updated_at
    from public.carts c
    where c.user_id = v_user
    order by c.product_id
    for update
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'product_id', lc.product_id,
        'quantity', lc.quantity,
        'updated_at', lc.updated_at
      ) order by lc.product_id
    ),
    '[]'::jsonb
  )
  into v_cart_snapshot
  from locked_cart lc;

  -- Recheck after acquiring cart locks: another identical request may have
  -- committed while this transaction waited for those locks.
  select o.id, o.total, o.status::text
    into v_order_id, v_total, v_status
  from public.orders o
  where o.buyer_id = v_user and o.request_id = p_request_id;

  if found then
    return jsonb_build_object(
      'order_id', v_order_id,
      'total', v_total,
      'currency', 'MMK',
      'status', v_status,
      'payment_method', 'cod',
      'idempotent_replay', true
    );
  end if;

  v_cart_count := jsonb_array_length(v_cart_snapshot);
  if v_cart_count = 0 then
    raise exception 'cart is empty';
  end if;

  -- Unique index prevents duplicate orders even under concurrent requests.
  insert into public.orders (buyer_id, request_id, status, total, currency, shipping_note)
  values (
    v_user,
    p_request_id,
    'pending',
    0,
    'MMK',
    jsonb_build_object(
      'name', trim(p_delivery_name),
      'phone', trim(p_delivery_phone),
      'address', trim(p_delivery_address)
    )::text
  )
  on conflict (buyer_id, request_id) where request_id is not null do nothing
  returning id into v_order_id;

  if v_order_id is null then
    select o.id, o.total, o.status::text
      into v_order_id, v_total, v_status
    from public.orders o
    where o.buyer_id = v_user and o.request_id = p_request_id;

    if v_order_id is null then
      raise exception 'checkout request could not be resolved';
    end if;

    return jsonb_build_object(
      'order_id', v_order_id,
      'total', v_total,
      'currency', 'MMK',
      'status', v_status,
      'payment_method', 'cod',
      'idempotent_replay', true
    );
  end if;

  -- Process only the captured cart snapshot; later cart additions are untouched.
  for v_item in
    select
      (item.value->>'product_id')::uuid as product_id,
      (item.value->>'quantity')::integer as quantity,
      (item.value->>'updated_at')::timestamptz as updated_at,
      p.seller_id,
      p.price
    from jsonb_array_elements(v_cart_snapshot) as item(value)
    join public.products p
      on p.id = (item.value->>'product_id')::uuid
    order by (item.value->>'product_id')::uuid
  loop
    insert into public.order_items (order_id, product_id, seller_id, quantity, unit_price)
    values (v_order_id, v_item.product_id, v_item.seller_id, v_item.quantity, v_item.price);

    delete from public.carts
    where user_id = v_user
      and product_id = v_item.product_id
      and quantity = v_item.quantity
      and updated_at = v_item.updated_at;

    get diagnostics v_deleted_count = row_count;
    if v_deleted_count <> 1 then
      raise exception 'cart changed during checkout; retry the request';
    end if;

    v_processed_count := v_processed_count + 1;
  end loop;

  if v_processed_count <> v_cart_count then
    raise exception 'one or more cart products are unavailable';
  end if;

  select o.total into v_total
  from public.orders o
  where o.id = v_order_id and o.buyer_id = v_user;

  return jsonb_build_object(
    'order_id', v_order_id,
    'total', v_total,
    'currency', 'MMK',
    'status', 'pending',
    'payment_method', 'cod',
    'idempotent_replay', false
  );
end;
$$;

revoke all on function private.create_cod_order_impl(text, text, text, uuid) from public, anon;
grant execute on function private.create_cod_order_impl(text, text, text, uuid) to authenticated;

-- Exposed RPC wrapper is SECURITY INVOKER and delegates to the private implementation.
create or replace function public.create_cod_order(
  p_delivery_name text,
  p_delivery_phone text,
  p_delivery_address text,
  p_request_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.create_cod_order_impl($1, $2, $3, $4);
$$;

revoke all on function public.create_cod_order(text, text, text, uuid) from public, anon;
grant execute on function public.create_cod_order(text, text, text, uuid) to authenticated;
