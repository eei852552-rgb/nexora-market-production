-- Retry-safe COD checkout and cart snapshot cleanup.
-- Apply only after reviewing this migration in the QA branch; do not run on production yet.

alter table public.orders
  add column if not exists request_id uuid;

create unique index if not exists orders_buyer_request_id_uidx
  on public.orders (buyer_id, request_id)
  where request_id is not null;

-- Remove browser-side order creation. Checkout must go through the guarded RPC.
drop policy if exists orders_buyer_insert on public.orders;
drop policy if exists order_items_buyer_insert on public.order_items;
revoke insert on public.orders, public.order_items from anon, authenticated;

-- Disable the former three-argument RPC so clients cannot bypass the idempotency key.
revoke all on function public.create_cod_order(text, text, text) from public, anon, authenticated;

create or replace function public.create_cod_order(
  p_delivery_name text,
  p_delivery_phone text,
  p_delivery_address text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_total numeric;
  v_status text;
  v_cart_count integer;
  v_processed_count integer := 0;
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

  -- Return the original order for a repeated request, even if its cart is now empty.
  select id, total, status into v_order_id, v_total, v_status
  from public.orders
  where buyer_id = v_user and request_id = p_request_id;

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

  -- Lock the buyer's current cart snapshot in stable order before creating the order.
  perform c.product_id
  from public.carts c
  where c.user_id = v_user
  order by c.product_id
  for update;

  -- A concurrent retry may have waited while the first request consumed the cart.
  select id, total, status into v_order_id, v_total, v_status
  from public.orders
  where buyer_id = v_user and request_id = p_request_id;

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

  select count(*) into v_cart_count
  from public.carts
  where user_id = v_user;

  if v_cart_count = 0 then
    raise exception 'cart is empty';
  end if;

  -- The partial unique index makes concurrent retries converge on one order.
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
    select id, total, status into v_order_id, v_total, v_status
    from public.orders
    where buyer_id = v_user and request_id = p_request_id;

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

  for v_item in
    select c.product_id, c.quantity, c.updated_at, p.seller_id, p.price
    from public.carts c
    join public.products p on p.id = c.product_id
    where c.user_id = v_user
    order by c.product_id
    for update of c
  loop
    insert into public.order_items (order_id, product_id, seller_id, quantity, unit_price)
    values (v_order_id, v_item.product_id, v_item.seller_id, v_item.quantity, v_item.price);

    -- Delete only the exact cart row snapshot consumed by this order.
    delete from public.carts
    where user_id = v_user
      and product_id = v_item.product_id
      and quantity = v_item.quantity
      and updated_at = v_item.updated_at;

    v_processed_count := v_processed_count + 1;
  end loop;

  if v_processed_count <> v_cart_count then
    raise exception 'one or more cart products are unavailable';
  end if;

  select total into v_total
  from public.orders
  where id = v_order_id and buyer_id = v_user;

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

revoke all on function public.create_cod_order(text, text, text, uuid) from public, anon;
grant execute on function public.create_cod_order(text, text, text, uuid) to authenticated;
