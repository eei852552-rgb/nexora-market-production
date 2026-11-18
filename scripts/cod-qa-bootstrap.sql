-- Disposable PostgreSQL fixture shaped from the live Supabase column metadata.
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

create table public.profiles (
  id uuid primary key, display_name text not null default '', bio text not null default '',
  avatar_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.seller_profiles (id uuid primary key references public.profiles(id));
create table public.products (
  id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.seller_profiles(id),
  name text not null, description text not null default '', price numeric not null,
  currency text not null default 'MMK', image_url text, category text not null default 'Other',
  status text not null default 'draft', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), type text not null default 'Physical',
  stock integer, is_featured boolean not null default false, icon text not null default '📦'
);
create table public.carts (
  user_id uuid not null references public.profiles(id), product_id uuid not null references public.products(id),
  quantity integer not null default 1 check(quantity>0), updated_at timestamptz not null default now(),
  primary key(user_id,product_id)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(), buyer_id uuid not null references public.profiles(id),
  status text not null default 'pending', total numeric not null default 0,
  currency text not null default 'MMK', shipping_note text not null default '',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id), seller_id uuid not null references public.seller_profiles(id),
  quantity integer not null default 1, unit_price numeric not null, created_at timestamptz not null default now()
);

create or replace function public.nexora_order_guard() returns trigger
language plpgsql security definer set search_path=public,private as $$
begin
  if new.buyer_id is distinct from auth.uid() then raise exception 'buyer_id must match authenticated user'; end if;
  new.status := 'pending'; new.total := 0; new.currency := 'MMK'; return new;
end $$;
create trigger trg_nexora_order_guard before insert on public.orders
for each row execute function public.nexora_order_guard();

create or replace function public.nexora_order_item_guard() returns trigger
language plpgsql security definer set search_path=public,private as $$
declare p public.products;
begin
  select * into p from public.products where id=new.product_id for update;
  if not found or p.status <> 'published' then raise exception 'product is not available'; end if;
  if new.seller_id is distinct from p.seller_id or new.unit_price is distinct from p.price then
    raise exception 'order item seller or price is invalid';
  end if;
  if new.quantity <= 0 or p.stock is null or new.quantity > p.stock then raise exception 'insufficient stock'; end if;
  update public.products set stock=stock-new.quantity, updated_at=now() where id=p.id;
  return new;
end $$;
create trigger trg_nexora_order_item_guard before insert on public.order_items
for each row execute function public.nexora_order_item_guard();

create or replace function public.nexora_recalculate_order_total() returns trigger
language plpgsql security definer set search_path=public as $$
declare oid uuid;
begin
  oid := case when tg_op='DELETE' then old.order_id else new.order_id end;
  update public.orders set total=coalesce((select sum(unit_price*quantity) from public.order_items where order_id=oid),0),
    updated_at=now() where id=oid;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger trg_nexora_recalculate_order_total after insert or update or delete on public.order_items
for each row execute function public.nexora_recalculate_order_total();

grant usage on schema public, auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant select, insert, update, delete on public.carts to authenticated;
grant select on public.orders, public.order_items, public.products to authenticated;
