-- Functional smoke tests against the disposable PostgreSQL fixture.
\set ON_ERROR_STOP on
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333');
insert into public.profiles(id,display_name) values
 ('11111111-1111-4111-8111-111111111111','QA Buyer'),
 ('22222222-2222-4222-8222-222222222222','Other Buyer'),
 ('33333333-3333-4333-8333-333333333333','QA Seller');
insert into public.products(id,seller_id,name,price,stock,status)
values ('44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333','QA item',1250,10,'published');
insert into public.carts(user_id,product_id,quantity)
values ('11111111-1111-4111-8111-111111111111','44444444-4444-4444-8444-444444444444',2);

create temporary table qa_checkout_results (attempt text primary key, result jsonb not null);
grant select, insert on qa_checkout_results to authenticated;

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('role','authenticated',false);
insert into qa_checkout_results(attempt,result)
select 'first', public.create_cod_order('QA Buyer','0912345678','QA test address 123456','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
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
insert into qa_checkout_results(attempt,result)
select 'replay', public.create_cod_order('QA Buyer','0912345678','QA test address 123456','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
select set_config('role','none',false);
do $$
declare v_orders int; v_items int; v_stock int; v_first uuid; v_replay uuid; v_replay_flag boolean;
begin
  select (result->>'order_id')::uuid into v_first from qa_checkout_results where attempt='first';
  select (result->>'order_id')::uuid, (result->>'idempotent_replay')::boolean into v_replay, v_replay_flag from qa_checkout_results where attempt='replay';
  if v_first is distinct from v_replay or v_replay_flag is distinct from true then raise exception 'retry did not return the original order'; end if;
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

-- Verify wrapper/implementation grants and SECURITY modes.
do $$
declare v_impl_definer boolean; v_impl_empty_path boolean; v_wrapper_definer boolean;
begin
  if not has_schema_privilege('authenticated','private','USAGE') then raise exception 'authenticated lacks private schema usage'; end if;
  if not has_function_privilege('authenticated','private.create_cod_order_impl(text,text,text,uuid)','EXECUTE') then raise exception 'authenticated cannot execute private implementation'; end if;
  if has_function_privilege('anon','private.create_cod_order_impl(text,text,text,uuid)','EXECUTE') then raise exception 'anon can execute private implementation'; end if;
  if not has_function_privilege('authenticated','public.create_cod_order(text,text,text,uuid)','EXECUTE') then raise exception 'authenticated cannot execute COD wrapper'; end if;
  if has_function_privilege('anon','public.create_cod_order(text,text,text,uuid)','EXECUTE') then raise exception 'anon can execute COD wrapper'; end if;
  select prosecdef,
         coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%'
    into v_impl_definer,v_impl_empty_path
  from pg_proc where oid='private.create_cod_order_impl(text,text,text,uuid)'::regprocedure;
  select prosecdef into v_wrapper_definer from pg_proc where oid='public.create_cod_order(text,text,text,uuid)'::regprocedure;
  if v_impl_definer is distinct from true or v_impl_empty_path is distinct from true then raise exception 'private implementation security settings are incorrect'; end if;
  if v_wrapper_definer is distinct from false then raise exception 'public wrapper must be SECURITY INVOKER'; end if;
end $$;

-- Direct authenticated order/order-item INSERT must be revoked.
do $$
begin
  if has_table_privilege('authenticated','public.orders','INSERT') then raise exception 'authenticated can directly insert orders'; end if;
  if has_table_privilege('authenticated','public.order_items','INSERT') then raise exception 'authenticated can directly insert order_items'; end if;
end $$;

\echo 'PASS: COD runtime smoke tests'

  ) into v_impl_definer,v_impl_empty_path
  from pg_proc where oid='private.create_cod_order_impl(text,text,text,uuid)'::regprocedure;
  select prosecdef into v_wrapper_definer from pg_proc where oid='public.create_cod_order(text,text,text,uuid)'::regprocedure;
  if v_impl_definer is distinct from true or v_impl_empty_path is distinct from true then raise exception 'private implementation security settings are incorrect'; end if;
  if v_wrapper_definer is distinct from false then raise exception 'public wrapper must be SECURITY INVOKER'; end if;
end $$;

-- Direct authenticated order/order-item INSERT must be revoked.
do $$
begin
  if has_table_privilege('authenticated','public.orders','INSERT') then raise exception 'authenticated can directly insert orders'; end if;
  if has_table_privilege('authenticated','public.order_items','INSERT') then raise exception 'authenticated can directly insert order_items'; end if;
end $$;

\echo 'PASS: COD runtime smoke tests'
