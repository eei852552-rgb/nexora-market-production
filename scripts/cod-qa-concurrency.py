import json
import os
import subprocess
import sys
import time

BUYER = "11111111-1111-4111-8111-111111111111"
PRODUCT_A = "44444444-4444-4444-8444-444444444444"
PRODUCT_B = "55555555-5555-4555-8555-555555555555"
REQUEST_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

BASE_ENV = os.environ.copy()
BASE_ENV.setdefault("PGHOST", "localhost")
BASE_ENV.setdefault("PGPORT", "5432")
BASE_ENV.setdefault("PGUSER", "postgres")
BASE_ENV.setdefault("PGDATABASE", "nexora_qa")
BASE_ENV.setdefault("PGPASSWORD", "qa-only-password")


def psql(sql, app="cod-qa-observer", timeout=10):
    env = BASE_ENV.copy()
    env["PGAPPNAME"] = app
    result = subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-qAt", "-c", sql],
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(f"psql failed ({app}): {result.stderr.strip()}")
    return result.stdout.strip()


def wait_for(predicate, seconds, message):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise RuntimeError(message)


def stop(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def main():
    # This test runs only after cod-qa-integration.sql on a disposable CI database.
    # Buyer one has one cart row for PRODUCT_A; PRODUCT_B is a new concurrent cart addition.
    psql(
        f"""
        select set_config('nexora.test_admin','on',false);
        insert into public.products
          (id, seller_id, name, description, price, currency, category, status, stock)
        values
          ('{PRODUCT_B}', '33333333-3333-4333-8333-333333333333',
           'Concurrent cart addition', 'CI-only fixture', 900, 'MMK', 'Other', 'published', 5);
        select set_config('nexora.test_admin','off',false);
        """,
        app="cod-qa-seed",
    )
    existing = psql(
        f"select count(*) from public.carts where user_id='{BUYER}' and product_id='{PRODUCT_A}'",
        app="cod-qa-observer",
    )
    if existing != "1":
        raise RuntimeError(f"expected exactly one original cart row, found {existing}")

    holder_sql = f"""
    begin;
    select product_id from public.carts
      where user_id='{BUYER}' and product_id='{PRODUCT_A}'
      for update;
    select pg_sleep(8);
    commit;
    """
    holder_env = BASE_ENV.copy()
    holder_env["PGAPPNAME"] = "cod-qa-lock-holder"
    holder = subprocess.Popen(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-qAt", "-c", holder_sql],
        env=holder_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    checkouts = []
    try:
        wait_for(
            lambda: psql(
                "select count(*) from pg_stat_activity "
                "where application_name='cod-qa-lock-holder' "
                "and state='active' and query ilike '%pg_sleep%'",
                app="cod-qa-observer",
            ) == "1",
            4,
            "lock-holder did not acquire the cart row",
        )

        checkout_sql = f"""
        select set_config('request.jwt.claim.sub','{BUYER}',false);
        select set_config('role','authenticated',false);
        select public.create_cod_order(
          'QA Buyer', '0912345678', 'QA test address 123456', '{REQUEST_ID}'::uuid
        );
        """
        for name in ("cod-qa-checkout-a", "cod-qa-checkout-b"):
            env = BASE_ENV.copy()
            env["PGAPPNAME"] = name
            checkouts.append(subprocess.Popen(
                ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-qAt", "-c", checkout_sql],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ))

        wait_for(
            lambda: psql(
                "select count(*) from pg_stat_activity "
                "where application_name in ('cod-qa-checkout-a','cod-qa-checkout-b') "
                "and wait_event_type='Lock' and query ilike '%create_cod_order%'",
                app="cod-qa-observer",
            ) == "2",
            5,
            "both checkout sessions did not reach the cart lock concurrently",
        )

        # Insert a different cart row while both checkout calls are blocked on PRODUCT_A.
        # The in-flight checkout snapshot must not consume this later row.
        psql(
            f"insert into public.carts(user_id,product_id,quantity) "
            f"values ('{BUYER}','{PRODUCT_B}',1)",
            app="cod-qa-add-cart-row",
        )

        holder_out, holder_err = holder.communicate(timeout=12)
        if holder.returncode:
            raise RuntimeError(f"lock-holder failed: {holder_err.strip()}")

        results = []
        for process in checkouts:
            stdout, stderr = process.communicate(timeout=12)
            if process.returncode:
                raise RuntimeError(f"concurrent checkout failed: {stderr.strip()}")
            lines = [line.strip() for line in stdout.splitlines() if line.strip()]
            if not lines:
                raise RuntimeError("concurrent checkout returned no JSON result")
            results.append(json.loads(lines[-1]))

        order_ids = {item.get("order_id") for item in results}
        replay_flags = {item.get("idempotent_replay") for item in results}
        if len(order_ids) != 1 or replay_flags != {False, True}:
            raise RuntimeError(
                f"same-request calls did not converge on one order: {results}"
            )

        state = json.loads(psql(
            f"""
            select json_build_object(
              'orders',(select count(*) from public.orders
                where buyer_id='{BUYER}' and request_id='{REQUEST_ID}'),
              'items',(select count(*) from public.order_items oi
                join public.orders o on o.id=oi.order_id
                where o.buyer_id='{BUYER}' and o.request_id='{REQUEST_ID}'),
              'stock_a',(select stock from public.products where id='{PRODUCT_A}'),
              'stock_b',(select stock from public.products where id='{PRODUCT_B}'),
              'cart_a',(select count(*) from public.carts
                where user_id='{BUYER}' and product_id='{PRODUCT_A}'),
              'cart_b',(select count(*) from public.carts
                where user_id='{BUYER}' and product_id='{PRODUCT_B}'),
              'cart_b_quantity',(select coalesce(sum(quantity),0) from public.carts
                where user_id='{BUYER}' and product_id='{PRODUCT_B}'),
              'total',(select total from public.orders
                where buyer_id='{BUYER}' and request_id='{REQUEST_ID}')
            )::text;
            """,
            app="cod-qa-final-check",
        ))
        expected = {
            "orders": 1,
            "items": 1,
            "stock_a": 6,
            "stock_b": 5,
            "cart_a": 0,
            "cart_b": 1,
            "cart_b_quantity": 1,
            "total": 1250,
        }
        if state != expected:
            raise RuntimeError(f"concurrency/cart-snapshot state mismatch: {state}")
        print("PASS: concurrent same-request COD calls return one order and decrement stock once")
        print("PASS: a cart row added while checkout waits remains in the cart")
    finally:
        stop(holder)
        for process in checkouts:
            stop(process)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
