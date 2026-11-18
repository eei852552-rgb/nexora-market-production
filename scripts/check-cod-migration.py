from pathlib import Path
import re
import sys

sql_path = Path("supabase/migrations/202611190001_cod_checkout_idempotency.sql")
app_path = Path("app.js")
hardening_path = Path("supabase/production-hardening.sql")
fixture_path = Path("scripts/cod-qa-bootstrap.sql")
integration_path = Path("scripts/cod-qa-integration.sql")
sql = sql_path.read_text(encoding="utf-8").lower()
app = app_path.read_text(encoding="utf-8").lower()
hardening = hardening_path.read_text(encoding="utf-8").lower()
fixture = fixture_path.read_text(encoding="utf-8").lower()
integration = integration_path.read_text(encoding="utf-8").lower()

checks = {
    "request UUID stored on orders": bool(re.search(r"add column if not exists request_id uuid", sql)),
    "buyer/request unique index": "on public.orders (buyer_id, request_id)" in sql,
    "private implementation": "function private.create_cod_order_impl(" in sql,
    "private function checks authenticated user": "if v_user is null" in sql,
    "request UUID required": "if p_request_id is null" in sql,
    "public wrapper is invoker": "security invoker" in sql,
    "direct order inserts revoked": "revoke insert on public.orders, public.order_items from anon, authenticated" in sql,
    "cart snapshot locks and captures rows atomically": "with locked_cart as materialized" in sql and "for update" in sql,
    "cart snapshot includes updated_at": "'updated_at', lc.updated_at" in sql,
    "cart deletion matches snapshot version": "and updated_at = v_item.updated_at" in sql,
    "frontend sends request UUID": "p_request_id: requestid" in app,
    "frontend persists retry key": "sessionstorage.setitem(requeststoragekey, requestid)" in app,
    "frontend distinguishes replay from new cart": "result.idempotent_replay === true && state.cart.length > 0" in app,
    "frontend keeps request key when account refresh fails": "account data could not refresh" in app,
    "QA fixture matches live auth.users foreign keys": fixture.count("references auth.users(id)") >= 5 and "seller_profiles" not in fixture,
    "QA test seeds auth users before profiles": "insert into auth.users(id)" in integration,
    "QA tests private schema and function grants": "has_schema_privilege('authenticated','private','usage')" in integration and "has_function_privilege('anon','private.create_cod_order_impl(text,text,text,uuid)','execute')" in integration,
    "QA tests SECURITY DEFINER implementation with empty search path": "v_impl_definer" in integration and "array_to_string(proconfig" in integration and "search_path" in integration,
    "QA tests SECURITY INVOKER wrapper": "v_wrapper_definer" in integration,
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
