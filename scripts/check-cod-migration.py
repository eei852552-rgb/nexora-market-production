from pathlib import Path
import re
import sys

sql_path = Path("supabase/migrations/202611190001_cod_checkout_idempotency.sql")
acl_path = Path("supabase/migrations/202611200001_cod_checkout_acl_hardening.sql")
product_guard_path = Path("supabase/migrations/202611210001_product_stock_guard_alignment.sql")
workflow_path = Path(".github/workflows/cod-qa-check.yml")
app_path = Path("app.js")
hardening_path = Path("supabase/production-hardening.sql")
fixture_path = Path("scripts/cod-qa-bootstrap.sql")
integration_path = Path("scripts/cod-qa-integration.sql")
sql = sql_path.read_text(encoding="utf-8").lower()
acl_sql = acl_path.read_text(encoding="utf-8").lower()
product_guard_sql = product_guard_path.read_text(encoding="utf-8").lower()
workflow = workflow_path.read_text(encoding="utf-8").lower()
app = app_path.read_text(encoding="utf-8").lower()
hardening = hardening_path.read_text(encoding="utf-8").lower()
fixture = fixture_path.read_text(encoding="utf-8").lower()
integration = integration_path.read_text(encoding="utf-8").lower()
qa_acl_path = Path("scripts/qa-project-acl-hardening.sql")
qa_acl = qa_acl_path.read_text(encoding="utf-8").lower()

checks = {
    "product stock-guard alignment migration exists": product_guard_path.exists(),
    "product guard uses SECURITY DEFINER with empty search_path": "security definer" in product_guard_sql and "set search_path = ''" in product_guard_sql,
    "product guard preserves seller identity and status controls": "new.seller_id is distinct from old.seller_id" in product_guard_sql and "new.status is distinct from old.status" in product_guard_sql and "private.is_admin()" in product_guard_sql,
    "product guard does not require the buyer to be an approved seller": "private.is_approved_seller" not in product_guard_sql and "approved seller required" not in product_guard_sql,
    "CI fixture reproduces the QA-only approval guard before migration": "approved seller required" in fixture and "create trigger trg_nexora_product_guard" in fixture,
    "CI seeds products only while the fixture admin flag is enabled": integration.count("set_config('nexora.test_admin','on',false)") >= 2 and integration.count("set_config('nexora.test_admin','off',false)") >= 2,
    "CI applies product stock-guard alignment migration": "202611210001_product_stock_guard_alignment.sql" in workflow,
    "QA ACL script is explicitly limited to the separate QA project": "-- qa project only" in qa_acl and "nexora-market-qa" in qa_acl,
    "QA ACL script hardens postgres-owned default table grants only": "alter default privileges for role postgres" in qa_acl and "alter default privileges for role supabase_admin" not in qa_acl,
    "QA ACL script revokes broad table privileges": "revoke all privileges on table" in qa_acl and "from public, anon, authenticated" in qa_acl,
    "QA ACL script grants cart CRUD to authenticated users": "grant select, insert, update, delete on table public.carts to authenticated" in qa_acl,
    "QA ACL script grants read-only access to COD orders and items": "grant select on table public.order_items, public.orders to authenticated" in qa_acl,
    "QA ACL script requires cart INSERT privilege": "or not has_table_privilege('authenticated','public.carts','insert')" in qa_acl,
    "QA ACL script blocks elevated table privileges": all(f"has_table_privilege('{role}', t, '{priv}')" in qa_acl for role in ("anon", "authenticated") for priv in ("truncate", "references", "trigger")),
    "request UUID stored on orders": bool(re.search(r"add column if not exists request_id uuid", sql)),
    "buyer/request unique index": "on public.orders (buyer_id, request_id)" in sql,
    "private implementation": "function private.create_cod_order_impl(" in sql,
    "private function checks authenticated user": "if v_user is null" in sql,
    "request UUID required": "if p_request_id is null" in sql,
    "public wrapper is invoker": "security invoker" in sql,
    "COD ACL migration exists": acl_path.exists(),
    "all client privileges revoked on COD/catalog tables": "revoke all privileges on table" in acl_sql and "public.orders" in acl_sql and "public.order_items" in acl_sql and "public.carts" in acl_sql and "public.products" in acl_sql,
    "authenticated order/item access is read-only": "grant select on table public.orders, public.order_items to authenticated" in acl_sql,
    "cart is authenticated CRUD only": "grant select, insert, update, delete on table public.carts to authenticated" in acl_sql,
    "catalog is public-read and authenticated CRUD": "grant select on table public.products to anon, authenticated" in acl_sql and "grant insert, update, delete on table public.products to authenticated" in acl_sql,
    "cart snapshot locks and captures rows atomically": "with locked_cart as materialized" in sql and "for update" in sql,
    "cart snapshot includes updated_at": "'updated_at', lc.updated_at" in sql,
    "cart deletion matches snapshot version": "and updated_at = v_item.updated_at" in sql,
    "frontend sends request UUID": "p_request_id: requestid" in app,
    "frontend persists one pending retry key per buyer": "const requeststoragekey = `nexora:cod-request:${state.user.id}`" in app and "sessionstorage.setitem(requeststoragekey, requestid)" in app,
    "frontend does not discard pending retry key when cart changes": "keep any pending cod request id" in app,
    "frontend distinguishes replay from new cart": "result.idempotent_replay === true && state.cart.length > 0" in app,
    "frontend keeps request key when account refresh fails": "account data could not refresh" in app,
    "QA fixture matches live auth.users foreign keys": fixture.count("references auth.users(id)") >= 5 and "seller_profiles" not in fixture,
    "QA test seeds auth users before profiles": "insert into auth.users(id)" in integration,
    "QA tests private schema and function grants": "has_schema_privilege('authenticated','private','usage')" in integration and "has_function_privilege('anon','private.create_cod_order_impl(text,text,text,uuid)','execute')" in integration,
    "QA tests SECURITY DEFINER implementation with empty search path": "v_impl_definer" in integration and "proconfig[1]" in integration and "search_path" in integration,
    "QA tests SECURITY INVOKER wrapper": "v_wrapper_definer" in integration,
    "RLS policies use non-recursive private helpers": "private.is_order_seller" in sql and "private.is_order_buyer" in sql,
    "QA enables RLS on COD tables": "enable row level security" in fixture,
    "QA tests buyer and seller RLS isolation": "buyer one rls isolation failed" in integration and "seller rls visibility failed" in integration,
    "QA tests invalid delivery, missing request ID, and insufficient-stock rollback": "expected delivery validation failure" in integration and "expected missing request id failure" in integration and "expected insufficient stock failure" in integration,
    "QA tests unavailable-product rollback": "expected unavailable product failure" in integration and "unavailable product failure was not atomic" in integration,
    "QA tests request UUID is scoped to buyer": "other_buyer_same_request" in integration and "request uuid was not scoped to buyer" in integration,
    "QA tests private RLS helper grants": "anon can execute private rls helpers" in integration,
    "QA tests empty search_path on both RLS helpers": "seller_empty_path" in integration and "buyer_empty_path" in integration and integration.count("proconfig[1] = 'search_path=\"\"'") >= 2,
    "existing order guard prerequisite": "create trigger trg_nexora_order_guard before insert on public.orders" in hardening,
    "existing stock guard prerequisite": "create trigger trg_nexora_order_item_guard before insert on public.order_items" in hardening,
    "existing order total trigger prerequisite": "create trigger trg_nexora_recalculate_order_total after insert or update or delete on public.order_items" in hardening,
}
for label, passed in checks.items():
    print(f'{"PASS" if passed else "FAIL"}: {label}')

forbidden = [r"\bdrop\s+table\b", r"\btruncate\b", r"\bdelete\s+from\s+public\.(orders|order_items)\b"]
for pattern in forbidden:
    if re.search(pattern, sql):
        print(f"FAIL: forbidden destructive SQL matched: {pattern}")
        checks[f"no {pattern}"] = False

if not all(checks.values()):
    sys.exit(1)

print(f"PASS: {len(checks)} COD migration static checks")
print("NOTE: static checks do not replace PostgreSQL execution/integration QA.")
