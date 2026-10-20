-- Applied to Supabase project nbhfdiiehukdtusxksni as migration:
-- harden_product_moderation_and_order_integrity
-- This is intentionally separate from the original foundation schema.

create or replace function public.nexora_product_guard() returns trigger language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then if tg_op='INSERT' then if new.seller_id is distinct from auth.uid() then raise exception 'seller_id must match the authenticated user'; end if; new.status := 'draft'; elsif tg_op='UPDATE' then if new.seller_id is distinct from old.seller_id then raise exception 'seller_id cannot change'; end if; if new.status is distinct from old.status then new.status := old.status; end if; end if; end if; return new; end; $$;
drop trigger if exists trg_nexora_product_guard on public.products;
create trigger trg_nexora_product_guard before insert or update on public.products for each row execute function public.nexora_product_guard();

create or replace function public.nexora_order_guard() returns trigger language plpgsql security definer set search_path=public,private as $$ begin if new.buyer_id is distinct from auth.uid() then raise exception 'buyer_id must match the authenticated user'; end if; new.status := 'pending'; new.total := 0; new.currency := 'MMK'; return new; end; $$;
drop trigger if exists trg_nexora_order_guard on public.orders;
create trigger trg_nexora_order_guard before insert on public.orders for each row execute function public.nexora_order_guard();

create or replace function public.nexora_order_item_guard() returns trigger language plpgsql security definer set search_path=public,private as $$ declare p public.products; begin select * into p from public.products where id=new.product_id for update; if not found or p.status <> 'published' then raise exception 'product is not available'; end if; if new.seller_id is distinct from p.seller_id or new.unit_price is distinct from p.price then raise exception 'order item seller or price is invalid'; end if; if new.quantity <= 0 or p.stock is null or new.quantity > p.stock then raise exception 'insufficient stock'; end if; update public.products set stock=stock-new.quantity, updated_at=now() where id=p.id; return new; end; $$;
drop trigger if exists trg_nexora_order_item_guard on public.order_items;
create trigger trg_nexora_order_item_guard before insert on public.order_items for each row execute function public.nexora_order_item_guard();

create or replace function public.nexora_recalculate_order_total() returns trigger language plpgsql security definer set search_path=public as $$ declare oid uuid; begin oid := case when tg_op='DELETE' then old.order_id else new.order_id end; update public.orders set total=coalesce((select sum(unit_price*quantity) from public.order_items where order_id=oid),0), updated_at=now() where id=oid; return case when tg_op='DELETE' then old else new end; end; $$;
drop trigger if exists trg_nexora_recalculate_order_total on public.order_items;
create trigger trg_nexora_recalculate_order_total after insert or update or delete on public.order_items for each row execute function public.nexora_recalculate_order_total();

drop policy if exists sellers_can_view_relevant_orders on public.orders;
create policy sellers_can_view_relevant_orders on public.orders for select to authenticated using (exists(select 1 from public.order_items oi where oi.order_id=orders.id and oi.seller_id=auth.uid()));
create index if not exists order_items_order_id_idx on public.order_items(order_id);
create index if not exists order_items_seller_id_idx on public.order_items(seller_id);

-- Keep trigger internals out of the browser-callable RPC surface.
revoke execute on function public.nexora_product_guard() from public, anon, authenticated;
revoke execute on function public.nexora_order_guard() from public, anon, authenticated;
revoke execute on function public.nexora_order_item_guard() from public, anon, authenticated;
revoke execute on function public.nexora_recalculate_order_total() from public, anon, authenticated;
