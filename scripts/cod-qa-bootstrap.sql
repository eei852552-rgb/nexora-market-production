-- Disposable PostgreSQL fixture shaped from the live Supabase column metadata.
-- COD trigger bodies below are copied from the current production definitions.
-- This is CI-only and contains no production data.
create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create schema private;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create or replace function private.is_admin() returns boolean language sql stable as $$ select false $$;

create table auth.users (id uuid primary key);
create table public.profiles (
  id uuid primary key references auth.users(id), display_name text not null default '', bio text not null default '',
  avatar_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(), seller_id uuid not null references auth.users(id),
  name text not null, description text not null default '', price numeric not null,
  currency text not null default 'MMK', image_url text, category text not null default 'Other',
  status text not null default 'draft', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), type text not null default 'Physical',
  stock integer, is_featured boolean not null default false, icon text not null default '📦'
);
create table public.carts (
  user_id uuid not null references auth.users(id), product_id uuid not null references public.products(id),
  quantity integer not null default 1 check(quantity>0), updated_at timestamptz not null default now(),
  primary key(user_id,product_id)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(), buyer_id uuid not null references auth.users(id),
  status text not null default 'pending', total numeric not null default 0,
  currency text not null default 'MMK', shipping_note text not null default '',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id), seller_id uuid not null references auth.users(id),
  quantity integer not null default 1, unit_price numeric not null, created_at timestamptz not null default now()
);

create or replace function public.nexora_order_guard()
returns trigger language plpgsql security definer set search_path=public,private
as $function$
begin
  if new.buyer_id is distinct from auth.uid() then
    raise exception 'buyer_id must match the authenticated user';
  end if;
  new.status := 'pending';
  new.total := 0;
  new.currency := 'MMK';
  return new;
end;
$function$;
create trigger trg_nexora_order_guard before insert on public.orders
for each row execute function public.nexora_order_guard();

create or replace function public.nexora_order_item_guard()
returns trigger language plpgsql security definer set search_path=public,private
as $function$
declare p public.products;
begin
  select * into p from public.products where id=new.product_id for update;
  if not found or p.status <> 'published' then
    raise exception 'product is not available';
  end if;
  if new.seller_id is distinct from p.seller_id or new.unit_price is distinct from p.price then
    raise exception 'order item seller or price is invalid';
  end if;
  if new.quantity <= 0 or p.stock is null or new.quantity > p.stock then
    raise exception 'insufficient stock';
  end if;
  update public.products set stock=stock-new.quantity, updated_at=now() where id=p.id;
  return new;
end;
$function$;
create trigger trg_nexora_order_item_guard before insert on public.order_items
for each row execute function public.nexora_order_item_guard();

create or replace function public.nexora_recalculate_order_total()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare oid uuid;
begin
  oid := case when tg_op='DELETE' then old.order_id else new.order_id end;
  update public.orders
  set total=coalesce((select sum(unit_price*quantity) from public.order_items where order_id=oid),0),
      updated_at=now()
  where id=oid;
  return case when tg_op='DELETE' then old else new end;
end;
$function$;
create trigger trg_nexora_recalculate_order_total after insert or update or delete on public.order_items
for each row execute function public.nexora_recalculate_order_total();

-- Reproduce the live RLS shape, including the original mutually recursive
-- seller-orders / participant-order-items policies. The COD migration must
-- replace those policies with non-recursive private helper functions.
alter table public.carts enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

create policy carts_owner_all on public.carts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy orders_buyer_read on public.orders for select to authenticated
  using (buyer_id = auth.uid());
create policy sellers_can_view_relevant_orders on public.orders for select to authenticated
  using (exists (
    select 1 from public.order_items oi
    where oi.order_id = orders.id and oi.seller_id = auth.uid()
  ));
create policy order_items_participant_read on public.order_items for select to authenticated
  using (
    seller_id = auth.uid()
    or exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.buyer_id = auth.uid()
    )
  );

create or replace function public.create_cod_order(p_delivery_name text,p_delivery_phone text,p_delivery_address text)
returns jsonb language sql security invoker set search_path=public as $codstub$ select '{}'::jsonb $codstub$;
grant execute on function public.create_cod_order(text,text,text) to authenticated;

grant usage on schema public, auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant select, insert, update, delete on public.carts to authenticated;
grant select on public.orders, public.order_items, public.products to authenticated;
