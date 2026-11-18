from pathlib import Path
import re
import sys

sql_path = Path("supabase/migrations/202611190001_cod_checkout_idempotency.sql")
app_path = Path("app.js")
sql = sql_path.read_text(encoding="utf-8").lower()
app = app_path.read_text(encoding="utf-8")

checks = {
    "request UUID stored on orders": bool(re.search(r"add column if not exists request_id uuid", sql)),
    "buyer/request unique index": "on public.orders (buyer_id, request_id)" in sql,
    "private implementation": "function private.create_cod_order_impl(" in sql,
    "private function checks authenticated user": "if v_user is null" in sql,
    "request UUID required": "if p_request_id is null" in sql,
    "public wrapper is invoker": "security invoker" in sql,
    "direct order inserts revoked": "revoke insert on public.orders, public.order_items from anon, authenticated" in sql,
    "cart snapshot includes updated_at": "'updated_at', c.updated_at" in sql,
    "cart deletion matches snapshot version": "and updated_at = v_item.updated_at" in sql,
    "frontend sends request UUID": "p_request_id: requestid" in app.lower(),
    "frontend persists retry key": "sessionstorage.setitem(requeststoragekey, requestid)" in app.lower(),
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
