-- Applied in Supabase project nbhfdiiehukdtusxksni.
-- Defense-in-depth: RLS remains authoritative; ACLs expose only required operations.

create or replace function public.nexora_ad_guard() returns trigger language plpgsql security definer set search_path=public, private as $$ begin if not private.is_admin() then if tg_op='INSERT' then if new.seller_id is distinct from auth.uid() then raise exception 'seller_id must match the authenticated user'; end if; if not private.is_approved_seller() then raise exception 'approved seller required'; end if; new.status := 'draft'; elsif tg_op='UPDATE' then if new.seller_id is distinct from old.seller_id then raise exception 'seller_id cannot change'; end if; if not private.is_approved_seller() then raise exception 'approved seller required'; end if; if new.status is distinct from old.status then new.status := old.status; end if; end if; end if; return new; end; $$;
drop trigger if exists nexora_ad_guard_trigger on public.advertisements;
create trigger nexora_ad_guard_trigger before insert or update on public.advertisements for each row execute function public.nexora_ad_guard();
revoke execute on function public.nexora_ad_guard() from public, anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='products_description_length_check') then alter table public.products add constraint products_description_length_check check (char_length(description) <= 5000); end if;
  if not exists (select 1 from pg_constraint where conname='products_category_length_check') then alter table public.products add constraint products_category_length_check check (char_length(trim(category)) between 1 and 80); end if;
  if not exists (select 1 from pg_constraint where conname='products_price_upper_check') then alter table public.products add constraint products_price_upper_check check (price <= 1000000000); end if;
  if not exists (select 1 from pg_constraint where conname='products_stock_nonnegative_check') then alter table public.products add constraint products_stock_nonnegative_check check (stock is null or stock >= 0); end if;
  if not exists (select 1 from pg_constraint where conname='products_currency_mmk_check') then alter table public.products add constraint products_currency_mmk_check check (currency = 'MMK'); end if;
  if not exists (select 1 from pg_constraint where conname='products_https_image_check') then alter table public.products add constraint products_https_image_check check (image_url is null or image_url ~* '^https://'); end if;
  if not exists (select 1 from pg_constraint where conname='advertisements_https_image_check') then alter table public.advertisements add constraint advertisements_https_image_check check (image_url is null or image_url ~* '^https://'); end if;
  if not exists (select 1 from pg_constraint where conname='advertisements_https_target_check') then alter table public.advertisements add constraint advertisements_https_target_check check (target_url is null or target_url ~* '^https://'); end if;
end $$;

revoke all on public.admin_roles, public.profiles, public.products, public.reviews, public.orders, public.order_items, public.carts, public.wishlists, public.seller_applications, public.advertisements, public.commissions, public.test_connection from public, anon, authenticated;
grant select on public.products, public.reviews, public.advertisements to anon;
grant select on public.admin_roles to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, insert on public.orders to authenticated;
grant select, insert on public.order_items to authenticated;
grant select, insert, update, delete on public.carts, public.wishlists, public.seller_applications, public.advertisements, public.reviews to authenticated;
grant select, insert, update, delete on public.commissions to authenticated;
