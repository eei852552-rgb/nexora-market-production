-- Applied to Supabase project nbhfdiiehukdtusxksni as add_auth_cart_and_cod_checkout.
-- This targets the existing production schema, not the older foundation draft.

create table if not exists public.carts (user_id uuid not null references auth.users(id) on delete cascade, product_id uuid not null references public.products(id) on delete cascade, quantity integer not null default 1 check (quantity > 0), updated_at timestamptz not null default now(), primary key (user_id, product_id));
create table if not exists public.wishlists (user_id uuid not null references auth.users(id) on delete cascade, product_id uuid not null references public.products(id) on delete cascade, created_at timestamptz not null default now(), primary key (user_id, product_id));
alter table public.carts enable row level security;
alter table public.wishlists enable row level security;
drop policy if exists carts_owner_all on public.carts;
create policy carts_owner_all on public.carts for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists wishlists_owner_all on public.wishlists;
create policy wishlists_owner_all on public.wishlists for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create or replace function public.handle_new_user_profile() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles (id, display_name, bio) values (new.id, coalesce(nullif(new.raw_user_meta_data->>'display_name',''), split_part(coalesce(new.email,''),'@',1)), '') on conflict (id) do nothing; return new; end; $$;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users for each row execute function public.handle_new_user_profile();
revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;
drop policy if exists orders_buyer_insert on public.orders;
create policy orders_buyer_insert on public.orders for insert to authenticated with check (buyer_id = auth.uid() and exists (select 1 from public.carts c where c.user_id = auth.uid()));
create or replace function public.create_cod_order(p_delivery_name text, p_delivery_phone text, p_delivery_address text) returns jsonb language plpgsql security invoker set search_path=public as $$ declare v_user uuid := auth.uid(); v_order_id uuid; v_total numeric; v_count integer; v_item record; begin if v_user is null then raise exception 'authentication required'; end if; if char_length(trim(coalesce(p_delivery_name,''))) < 2 or char_length(trim(coalesce(p_delivery_phone,''))) < 6 or char_length(trim(coalesce(p_delivery_address,''))) < 8 then raise exception 'delivery details are incomplete'; end if; select count(*) into v_count from public.carts where user_id = v_user; if v_count = 0 then raise exception 'cart is empty'; end if; insert into public.orders (buyer_id, status, total, currency, shipping_note) values (v_user, 'pending', 0, 'MMK', jsonb_build_object('name',trim(p_delivery_name),'phone',trim(p_delivery_phone),'address',trim(p_delivery_address))::text) returning id into v_order_id; for v_item in select c.product_id, c.quantity, p.seller_id, p.price from public.carts c join public.products p on p.id = c.product_id where c.user_id = v_user order by c.product_id for update of c loop insert into public.order_items (order_id, product_id, seller_id, quantity, unit_price) values (v_order_id, v_item.product_id, v_item.seller_id, v_item.quantity, v_item.price); end loop; select total into v_total from public.orders where id = v_order_id; delete from public.carts where user_id = v_user; return jsonb_build_object('order_id',v_order_id,'total',v_total,'currency','MMK','status','pending','payment_method','cod'); end; $$;
revoke all on function public.create_cod_order(text,text,text) from public, anon;
grant execute on function public.create_cod_order(text,text,text) to authenticated;
create index if not exists carts_product_id_idx on public.carts(product_id);
create index if not exists wishlists_product_id_idx on public.wishlists(product_id);
