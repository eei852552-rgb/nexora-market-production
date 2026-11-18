-- Functional smoke tests against the disposable PostgreSQL fixture.
\set ON_ERROR_STOP on
insert into public.profiles(id,display_name) values
 ('11111111-1111-4111-8111-111111111111','QA Buyer'),
 ('22222222-2222-4222-8222-222222222222','Other Buyer');
insert into public.seller_profiles(id) values ('33333333-3333-4333-8333-333333333333');
insert into public.products(id,seller_id,name,price,stock,status)
values ('44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333','QA item',1250,10,'published');
insert into public.carts(user_id,product_id,quantity)
values ('11111111-1111-4111-8111-111111111111','44444444-4444-4444-8444-444444444444',2);

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('role','authenticated',false);
select public.create_cod_order('QA Buyer','0912345678','QA test address 123456','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid) as first_result \gset
select set_config('role','none',false);

do $$
declare v_order_count int; v_item_count int; v_stock int; v_cart_count int; v_total numeric;
begin
  select count(*) into v_order_count from public.orders where buyer_id='11111111-1111-4111-8111-111111111111';
  select count(*) into v_item_count from public.order_items;
  select stock into v_stock from public.products where id='44444444-4444-4444-8444-444444444444';
  select count(*) into v_cart_count from public.carts where user_id='11111111-1111-4111-8111-111111111111';
  select total into v_total from public.orders where buyer_id='11111111-1111-4111-8111-111111111111';
  if v_order_count<>1 or v_item_count<>1 or v_stock<>8 or v_cart_count<>0 or v_total<>2500 then
    raise exception 'first checkout assertions failed: orders %, items %, stock %, cart %, total %',v_order_count,v_item_count,v_stock,v_cart_count,v_total;
  end if;
end $$;

-- Retry with the exact same request UUID must return the same order without stock/cart changes.
select set_config('role','authenticated',false);
select public.create_cod_order('QA Buyer','0912345678','QA test address 123456') as replay_result \gset
select set_config('role','none',false);
do $$
declare v_orders int; v_items int; v_stock int;
begin
  select count(*) into v_orders from public.orders where buyer_id='11111111-1111-4111-8111-111111111111';
  select count(*) into v_items from public.order_items;
  select stock into v_stock from public.products where id='44444444-4444-4444-8444-444444444444';
  if v_orders<>1 or v_items<>1 or v_stock<>8 then raise exception 'idempotent replay duplicated effects'; end if;
end $$;

-- A different buyer cannot replay the first buyer's request; with no cart it must fail.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('role','authenticated',false);
do $$ begin
  begin
    perform public.create_cod_order('Other Buyer','0912345678','QA test address 123456','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
    raise exception 'expected empty cart failure';
  exception when others then
    if sqlerrm='expected empty cart failure' then raise; end if;
    if sqlerrm not like '%cart is empty%' then raise; end if;
  end;
end $$;
select set_config('role','none',false);

-- Direct authenticated order/order-item INSERT must be revoked.
do $$
begin
  if has_table_privilege('authenticated','public.orders','INSERT') then raise exception 'authenticated can directly insert orders'; end if;
  if has_table_privilege('authenticated','public.order_items','INSERT') then raise exception 'authenticated can directly insert order_items'; end if;
  if not has_function_privilege('authenticated','public.create_cod_order(text,text,text,uuid)','EXECUTE') then raise exception 'authenticated cannot execute COD RPC'; end if;
end $$;

\echo 'PASS: COD runtime smoke tests'
