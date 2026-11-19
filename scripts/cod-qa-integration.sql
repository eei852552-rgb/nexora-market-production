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

-- Failure paths must roll back completely and preserve the cart and stock.
insert into public.products(id,seller_id,name,description,price,currency,category,status,stock)
values
 ('66666666-6666-4666-8666-666666666666','33333333-3333-4333-8333-333333333333','Low stock QA item','CI fixture',500,'MMK','Other','published',1),
 ('77777777-7777-4777-8777-777777777777','33333333-3333-4333-8333-333333333333','Draft QA item','CI fixture',750,'MMK','Other','draft',5);
insert into public.carts(user_id,product_id,quantity) values
 ('11111111-1111-4111-8111-111111111111','66666666-6666-4666-8666-666666666666',2),
 ('11111111-1111-4111-8111-111111111111','77777777-7777-4777-8777-777777777777',1);

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('role','authenticated',false);
do $failure$
begin
  begin
    perform public.create_cod_order('', '0912345678', 'QA test address 123456',
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid);
    raise exception 'expected delivery validation failure';
  exception when others then
    if sqlerrm='expected delivery validation failure' then raise; end if;
    if sqlerrm not like '%delivery details are incomplete%' then raise; end if;
  end;
  begin
    perform public.create_cod_order('QA Buyer', '0912345678', 'QA test address 123456', null);
    raise exception 'expected missing request ID failure';
  exception when others then
    if sqlerrm='expected missing request ID failure' then raise; end if;
    if sqlerrm not like '%checkout request ID is required%' then raise; end if;
  end;
  begin
    perform public.create_cod_order('QA Buyer', '0912345678', 'QA test address 123456',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid);
    raise exception 'expected insufficient stock failure';
  exception when others then
    if sqlerrm='expected insufficient stock failure' then raise; end if;
    if sqlerrm not like '%insufficient stock%' then raise; end if;
  end;
end
$failure$;
select set_config('role','none',false);

do $rollback$
declare v_low_stock integer; v_draft_stock integer; v_cart_rows integer; v_orders integer; v_items integer;
begin
  select stock into v_low_stock from public.products where id='66666666-6666-4666-8666-666666666666';
  select stock into v_draft_stock from public.products where id='77777777-7777-4777-8777-777777777777';
  select count(*) into v_cart_rows from public.carts
    where user_id='11111111-1111-4111-8111-111111111111'
      and product_id in ('66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777');
  select count(*) into v_orders from public.orders
    where request_id in (
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    );
  select count(*) into v_items from public.order_items
    where product_id in ('66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777');
  if v_low_stock<>1 or v_draft_stock<>5 or v_cart_rows<>2 or v_orders<>0 or v_items<>0 then
    raise exception 'failed COD attempts were not atomic: low stock %, draft stock %, cart rows %, orders %, items %',
      v_low_stock,v_draft_stock,v_cart_rows,v_orders,v_items;
  end if;
end
$rollback$;

-- An unavailable/draft product must also fail atomically.
delete from public.carts
where user_id='11111111-1111-4111-8111-111111111111'
  and product_id='66666666-6666-4666-8666-666666666666';
select set_config('role','authenticated',false);
do $unavailable$
begin
  begin
    perform public.create_cod_order('QA Buyer', '0912345678', 'QA test address 123456',
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid);
    raise exception 'expected unavailable product failure';
  exception when others then
    if sqlerrm='expected unavailable product failure' then raise; end if;
    if sqlerrm not like '%product is not available%' then raise; end if;
  end;
end
$unavailable$;
select set_config('role','none',false);
do $unavailable_check$
begin
  if (select count(*) from public.orders where request_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')<>0
     or (select count(*) from public.order_items where product_id='77777777-7777-4777-8777-777777777777')<>0
     or (select stock from public.products where id='77777777-7777-4777-8777-777777777777')<>5
     or (select count(*) from public.carts where user_id='11111111-1111-4111-8111-111111111111'
         and product_id='77777777-7777-4777-8777-777777777777')<>1 then
    raise exception 'unavailable product failure was not atomic';
  end if;
end
$unavailable_check$;
delete from public.carts
where user_id='11111111-1111-4111-8111-111111111111'
  and product_id='77777777-7777-4777-8777-777777777777';

-- A second buyer using the same UUID must create their own order, never replay
-- the first buyer's order. The unique key is scoped to (buyer_id, request_id).
insert into public.carts(user_id,product_id,quantity)
values ('22222222-2222-4222-8222-222222222222','44444444-4444-4444-8444-444444444444',1);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('role','authenticated',false);
insert into qa_checkout_results(attempt,result)
select 'other_buyer_same_request',
  public.create_cod_order('Other Buyer','0912345678','QA test address 123456',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
select set_config('role','none',false);
do $buyer_scope$
declare v_first uuid; v_other uuid; v_orders integer; v_stock integer; v_cart integer;
begin
  select (result->>'order_id')::uuid into v_first from qa_checkout_results where attempt='first';
  select (result->>'order_id')::uuid into v_other from qa_checkout_results where attempt='other_buyer_same_request';
  select count(*) into v_orders from public.orders where buyer_id='22222222-2222-4222-8222-222222222222';
  select stock into v_stock from public.products where id='44444444-4444-4444-8444-444444444444';
  select count(*) into v_cart from public.carts where user_id='22222222-2222-4222-8222-222222222222';
  if v_first is null or v_other is null or v_first=v_other or v_orders<>1 or v_stock<>7 or v_cart<>0 then
    raise exception 'request UUID was not scoped to buyer: first %, other %, orders %, stock %, cart %',
      v_first,v_other,v_orders,v_stock,v_cart;
  end if;
end
$buyer_scope$;

-- Verify wrapper/implementation grants and SECURITY modes.
do $$
declare v_impl_definer boolean; v_impl_empty_path boolean; v_wrapper_definer boolean;
begin
  if not has_schema_privilege('authenticated','private','USAGE') then raise exception 'authenticated lacks private schema usage'; end if;
  if not has_function_privilege('authenticated','private.create_cod_order_impl(text,text,text,uuid)','EXECUTE') then raise exception 'authenticated cannot execute private implementation'; end if;
  if has_function_privilege('anon','private.create_cod_order_impl(text,text,text,uuid)','EXECUTE') then raise exception 'anon can execute private implementation'; end if;
  if not has_function_privilege('authenticated','public.create_cod_order(text,text,text,uuid)','EXECUTE') then raise exception 'authenticated cannot execute COD wrapper'; end if;
  if has_function_privilege('anon','public.create_cod_order(text,text,text,uuid)','EXECUTE') then raise exception 'anon can execute COD wrapper'; end if;
  select prosecdef into v_impl_definer
  from pg_proc where oid='private.create_cod_order_impl(text,text,text,uuid)'::regprocedure;
  select proconfig[1] = 'search_path=""' into v_impl_empty_path
  from pg_proc where oid='private.create_cod_order_impl(text,text,text,uuid)'::regprocedure;
  select prosecdef into v_wrapper_definer
  from pg_proc where oid='public.create_cod_order(text,text,text,uuid)'::regprocedure;
  if v_impl_definer is distinct from true or v_impl_empty_path is distinct from true then raise exception 'private implementation security settings are incorrect'; end if;
  if v_wrapper_definer is distinct from false then raise exception 'public wrapper must be SECURITY INVOKER'; end if;
end $$;

-- Verify least-privilege grants. RLS does not protect TRUNCATE.
do $acl$
begin
  if not has_table_privilege('authenticated','public.orders','SELECT')
     or not has_table_privilege('authenticated','public.order_items','SELECT') then
    raise exception 'authenticated must retain order and order-item SELECT';
  end if;
  if has_table_privilege('anon','public.orders','SELECT')
     or has_table_privilege('anon','public.order_items','SELECT')
     or has_table_privilege('anon','public.carts','SELECT') then
    raise exception 'anon must not read private COD tables';
  end if;
  if has_table_privilege('anon','public.orders','INSERT')
     or has_table_privilege('anon','public.orders','UPDATE')
     or has_table_privilege('anon','public.orders','DELETE')
     or has_table_privilege('anon','public.orders','TRUNCATE')
     or has_table_privilege('anon','public.order_items','INSERT')
     or has_table_privilege('anon','public.order_items','UPDATE')
     or has_table_privilege('anon','public.order_items','DELETE')
     or has_table_privilege('anon','public.order_items','TRUNCATE')
     or has_table_privilege('anon','public.carts','INSERT')
     or has_table_privilege('anon','public.carts','UPDATE')
     or has_table_privilege('anon','public.carts','DELETE')
     or has_table_privilege('anon','public.carts','TRUNCATE') then
    raise exception 'anon retains an unsafe COD table privilege';
  end if;
  if has_table_privilege('authenticated','public.orders','INSERT')
     or has_table_privilege('authenticated','public.orders','UPDATE')
     or has_table_privilege('authenticated','public.orders','DELETE')
     or has_table_privilege('authenticated','public.orders','TRUNCATE')
     or has_table_privilege('authenticated','public.orders','REFERENCES')
     or has_table_privilege('authenticated','public.orders','TRIGGER')
     or has_table_privilege('authenticated','public.order_items','INSERT')
     or has_table_privilege('authenticated','public.order_items','UPDATE')
     or has_table_privilege('authenticated','public.order_items','DELETE')
     or has_table_privilege('authenticated','public.order_items','TRUNCATE')
     or has_table_privilege('authenticated','public.order_items','REFERENCES')
     or has_table_privilege('authenticated','public.order_items','TRIGGER') then
    raise exception 'authenticated retains an unsafe direct order privilege';
  end if;
  if not has_table_privilege('authenticated','public.carts','SELECT')
     or not has_table_privilege('authenticated','public.carts','INSERT')
     or not has_table_privilege('authenticated','public.carts','UPDATE')
     or not has_table_privilege('authenticated','public.carts','DELETE')
     or has_table_privilege('authenticated','public.carts','TRUNCATE')
     or has_table_privilege('authenticated','public.carts','REFERENCES')
     or has_table_privilege('authenticated','public.carts','TRIGGER') then
    raise exception 'authenticated cart grants are not least-privilege CRUD';
  end if;
  if not has_table_privilege('anon','public.products','SELECT')
     or not has_table_privilege('authenticated','public.products','SELECT')
     or not has_table_privilege('authenticated','public.products','INSERT')
     or not has_table_privilege('authenticated','public.products','UPDATE')
     or not has_table_privilege('authenticated','public.products','DELETE')
     or has_table_privilege('anon','public.products','TRUNCATE')
     or has_table_privilege('authenticated','public.products','TRUNCATE') then
    raise exception 'product grants do not match the public-read/authenticated-CRUD model';
  end if;
end $acl$;

-- The two buyer orders were created through the COD RPC above.
-- Add fresh owner-scoped carts, then exercise the actual RLS policies.
insert into public.carts(user_id,product_id,quantity) values
 ('11111111-1111-4111-8111-111111111111','44444444-4444-4444-8444-444444444444',1),
 ('22222222-2222-4222-8222-222222222222','44444444-4444-4444-8444-444444444444',1);

-- Buyer one sees only their own order, items, and cart.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('role','authenticated',false);
do $rls$
declare n_orders int; n_items int; n_carts int;
begin
  select count(*) into n_orders from public.orders;
  select count(*) into n_items from public.order_items;
  select count(*) into n_carts from public.carts;
  if n_orders<>1 or n_items<>1 or n_carts<>1 then
    raise exception 'buyer one RLS isolation failed: orders %, items %, carts %',n_orders,n_items,n_carts;
  end if;
end $rls$;
select set_config('role','none',false);

-- Buyer two sees only their own order, items, and cart.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select set_config('role','authenticated',false);
do $rls$
declare n_orders int; n_items int; n_carts int;
begin
  select count(*) into n_orders from public.orders;
  select count(*) into n_items from public.order_items;
  select count(*) into n_carts from public.carts;
  if n_orders<>1 or n_items<>1 or n_carts<>1 then
    raise exception 'buyer two RLS isolation failed: orders %, items %, carts %',n_orders,n_items,n_carts;
  end if;
end $rls$;
select set_config('role','none',false);

-- The seller sees both relevant orders/items, but neither buyer's cart.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select set_config('role','authenticated',false);
do $rls$
declare n_orders int; n_items int; n_carts int;
begin
  select count(*) into n_orders from public.orders;
  select count(*) into n_items from public.order_items;
  select count(*) into n_carts from public.carts;
  if n_orders<>2 or n_items<>2 or n_carts<>0 then
    raise exception 'seller RLS visibility failed: orders %, items %, carts %',n_orders,n_items,n_carts;
  end if;
end $rls$;
select set_config('role','none',false);

-- The policy helpers must be callable only by authenticated users and remain
-- SECURITY DEFINER with an empty search_path.
do $rls$
declare
  seller_definer boolean;
  buyer_definer boolean;
  seller_empty_path boolean;
  buyer_empty_path boolean;
begin
  if has_function_privilege('anon','private.is_order_seller(uuid)','EXECUTE')
     or has_function_privilege('anon','private.is_order_buyer(uuid)','EXECUTE') then
    raise exception 'anon can execute private RLS helpers';
  end if;
  select prosecdef, proconfig[1] = 'search_path=""'
    into seller_definer, seller_empty_path
    from pg_proc where oid='private.is_order_seller(uuid)'::regprocedure;
  select prosecdef, proconfig[1] = 'search_path=""'
    into buyer_definer, buyer_empty_path
    from pg_proc where oid='private.is_order_buyer(uuid)'::regprocedure;
  if seller_definer is distinct from true or buyer_definer is distinct from true then
    raise exception 'RLS helper functions must be SECURITY DEFINER';
  end if;
  if seller_empty_path is distinct from true or buyer_empty_path is distinct from true then
    raise exception 'RLS helper functions must have an empty search_path';
  end if;
end $rls$;

\echo 'PASS: COD runtime smoke tests'
