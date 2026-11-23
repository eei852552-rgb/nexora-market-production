# COD Checkout Idempotency Deployment Runbook

Status: review-only. This document does not authorize a production migration or deployment.

## Scope and safety boundary

- Repository: `eei852552-rgb/nexora-market-production`
- Candidate branch: `cod-idempotency-qa-20261119`
- Migration: `supabase/migrations/202611190001_cod_checkout_idempotency.sql`
- Supabase project: `nbhfdiiehukdtusxksni`
- The candidate migration is on an isolated Git branch. The separate Supabase project `nexora-market-qa` is active and its migration history contains `cod_checkout_idempotency`; a read-only audit confirms the request-ID index and four-argument RPC/private functions are present.
- Disposable PostgreSQL 16 CI and transaction-scoped SQL tests on the separate Supabase QA PostgreSQL 17.12 project provide database-level checkout evidence. Neither reproduces a real Supabase Auth session, PostgREST HTTP call, or signed-in browser checkout.
- A current read-only audit verifies table-level QA ACL hardening across all nine public tables: RLS is enabled and anon/authenticated have no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges. COD orders/items are SELECT-only for authenticated users; carts retain CRUD. The `supabase_admin` default ACL for future public tables remains broad and requires owner-level review before new public tables are created.
- Two pre-existing Auth users and two profile rows remain. No new persistent QA account, admin role, product, cart, or order was created; transaction-scoped fixtures from the prior QA test were rolled back. No production migration or deployment has occurred.
- Do not merge to `main`, apply to the live database, or deploy the frontend without explicit approval.

## Current QA verification snapshot — 2026-11-22

- QA project `nexora-market-qa` is active on PostgreSQL 17.12. The COD request-ID column/index, four-argument invoker RPC, and private implementation/RLS helpers are present.
- Current QA row counts: `auth.users=2`, `profiles=2`; the other eight public tables (`admin_roles`, `advertisements`, `carts`, `order_items`, `orders`, `products`, `seller_applications`, `wishlists`) are empty.
- Read-only role simulation passed for the current grants: anon can select catalog products but cannot select orders or insert orders/items; authenticated with a simulated JWT subject can read its own profile and select orders/items, but cannot directly insert orders/items. The four-argument COD RPC is executable by authenticated only.
- The available PostgREST log window had 14 events, all on `/`; no COD RPC or direct orders REST path was observed. Actual Auth/PostgREST and signed-in browser checkout remain unverified.
- QA Security Advisor: leaked-password protection disabled. Performance Advisor: 7 unindexed foreign keys and 6 multiple-permissive-policy findings.
- Production re-audit still shows no `orders.request_id`, only the legacy three-argument COD RPC, authenticated direct INSERT grants on orders/items, and broad anon/authenticated privileges on `public.reports` despite RLS being enabled. None of these production findings was changed.
- GitHub Actions run [44795228889](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44795228889) passed on candidate commit `3910fae39b3e3d7d2c2cb8d93a0ee7e5b8809e15`. CI used disposable PostgreSQL 16 and is not production verification.
- The candidate remains on its feature branch; `main`, live deployment, production database, and existing backups remain unchanged.

## Preflight — must all pass before any future production change

1. Confirm the target Supabase project ref is exactly `nbhfdiiehukdtusxksni`.
2. Confirm the feature branch tip and review the complete migration diff.
3. Take and verify a recoverable database backup or export. Confirm the restore path, not merely that a backup job exists.
4. Confirm the production schema still matches the migration prerequisites:
   - `orders.buyer_id`, `orders.status`, `orders.total`, `orders.currency`, `orders.shipping_note`
   - `order_items.order_id`, `product_id`, `seller_id`, `quantity`, `unit_price`
   - `carts.user_id`, `product_id`, `quantity`, `updated_at`
   - The order guard, stock guard, and order-total triggers
5. Recheck all current policies and grants on `orders`, `order_items`, and `carts`. The candidate migration deliberately replaces the mutually recursive seller/order-item read policies with narrow private helper functions.
6. Confirm `private` is not exposed through the Data API. Confirm authenticated role has only the required schema USAGE and function EXECUTE grants.
7. Run Supabase Security and Performance Advisors. Review every finding; do not dismiss unrelated warnings as part of this change.
8. Confirm all deployed clients call the four-argument `create_cod_order` RPC and supply a stable UUID request ID. The old three-argument RPC is removed by this migration.
9. Confirm customer support, delivery area, delivery fees, return process, and order operations are ready before enabling real customer checkout.
10. Confirm CI passes on the exact commit proposed for release.

## Apply sequence — future, approval required

1. Announce a checkout maintenance window and temporarily prevent new checkout attempts.
2. Reconfirm the backup and target project.
3. Apply the migration once through the approved Supabase migration workflow.
4. Verify the new `orders.request_id` column and partial unique index.
5. Verify the four-argument public RPC is executable by `authenticated` only; verify the private implementation and RLS helpers are not executable by `anon` or `PUBLIC`.
6. Verify `private` schema USAGE is limited to intended roles and that it is not an exposed API schema.
7. Run read-only checks for RLS enabled state, policies, function security modes, and grants.
8. Run a controlled test checkout with a designated test account and product only after a separate approval for test writes. Verify retry returns the same order and does not decrement stock twice.
9. Verify buyer order visibility, seller order visibility, and cross-buyer isolation using authenticated sessions.
10. Deploy the matching frontend only after database checks pass. Re-enable checkout after a successful end-to-end test.

## Postflight verification

- `orders.request_id` exists and the partial unique index is valid.
- `public.create_cod_order(text,text,text,uuid)` is SECURITY INVOKER.
- `private.create_cod_order_impl(text,text,text,uuid)` is SECURITY DEFINER with an empty search_path and explicit authentication check.
- `private.is_order_seller(uuid)` and `private.is_order_buyer(uuid)` are SECURITY DEFINER with an empty search_path, and have no EXECUTE grant to `anon` or `PUBLIC`.
- Authenticated users cannot directly INSERT into `orders` or `order_items`.
- Buyer sees only their own order/items; seller sees orders/items tied to their own products; neither can read another buyer's cart.
- Replaying the same buyer/request UUID returns the original order and does not create extra order items or decrement stock again.
- A new cart after an earlier checkout is not reported as submitted by an idempotent replay.
- No unexpected errors appear in Postgres or API logs.

## Rollback and recovery

There is intentionally no automatic SQL down-migration.

This migration drops the legacy three-argument `public.create_cod_order(text,text,text)` function and removes direct browser INSERT permissions. Recreating the old function or restoring the old INSERT policies from memory would be unsafe and could reintroduce the original checkout race or bypass controls.

If postflight checks fail:

1. Keep checkout disabled at the application level.
2. Do not drop `orders.request_id`, the unique index, or the private functions as an improvised rollback.
3. Do not restore direct INSERT grants or the old buyer INSERT policies.
4. Preserve logs and the exact migration commit; diagnose and prepare a reviewed forward-fix.
5. If a full database restore is genuinely required, use the verified preflight backup and the project's approved restore procedure during a maintenance window. A restore can discard writes made after the backup, so it requires explicit owner approval.
6. Keep the frontend and database versions compatible. The previous frontend calling the removed three-argument RPC will fail closed; it is not a safe rollback target.

## Known limitations before launch

- CI uses a disposable PostgreSQL fixture, not a complete Supabase Auth/PostgREST/Data API environment.
- Browser end-to-end checkout has not yet been verified.
- Supabase Free does not provide the paid database branching capability attempted during QA.
- Leaked-password protection was previously reported disabled in Supabase Auth; it remains a separate outstanding security setting and was not changed.
- This runbook is a checklist, not evidence that production has been migrated or is launch-ready.


## Transaction-scoped Supabase QA re-test — 2026-11-23

Target: separate QA project `gudvguwhqhuvpblwdcil` (`nexora-market-qa`), PostgreSQL 17.12. This test used the existing two QA Auth users plus one temporary Auth user inserted only inside the test transaction. A temporary admin role was assigned only to seed three published QA products. The test explicitly ended with `ROLLBACK`.

Assertions and results:

1. First call through `public.create_cod_order(text,text,text,uuid)` as database role `authenticated` created exactly one order and one order item. Total was 2,500 MMK; product A stock changed from 10 to 8.
2. Replaying the same buyer/request UUID returned the same order ID with `idempotent_replay=true`; order count, item count, and stock did not change.
3. A new cart item added after the first order remained in the cart after replaying the original request; the replay did not submit or consume it.
4. A second checkout contained a valid line followed by a line with insufficient stock. The RPC raised `insufficient stock`; the earlier line's order-item insert, stock decrement, and cart deletion were rolled back. Both cart rows remained; product B stock stayed 5 and product C stock stayed 1.
5. RLS visibility passed: buyer saw one order/item, an unrelated buyer saw zero, and the seller associated with the order item saw one.
6. All assertions passed. A post-rollback audit showed `auth.users=2`, `profiles=2`, `admin_roles=0`, and zero rows in products, carts, orders, order_items, advertisements, seller_applications, wishlists, and other marketplace tables.

Verification boundary: this is a transaction-scoped test against the actual Supabase QA PostgreSQL database using `SET ROLE authenticated` and simulated JWT subject claims. It is not an actual Supabase Auth HTTP session, PostgREST HTTP RPC, or signed-in browser checkout. No PostgREST COD request was observed in the available QA logs. Do not describe this as end-to-end or production verification.

A fresh read-only production audit on 2026-11-23 still found no `orders.request_id`, only the legacy three-argument COD RPC, authenticated direct INSERT grants on orders/items, and broad anon/authenticated grants on `public.reports` including TRUNCATE, REFERENCES, and TRIGGER. Production remains unchanged. No merge, deployment, migration, backup/restore, or persistent QA fixture was performed.


## COD order-item lookup index QA — 2026-11-24

- Added the additive migration `supabase/migrations/202611240001_cod_order_items_order_id_index.sql` to create `public.order_items(order_id)` support index `order_items_order_id_idx`.
- Applied the migration only to the separate QA project `nexora-market-qa` (`gudvguwhqhuvpblwdcil`, PostgreSQL 17.12). The QA migration history records it as `cod_order_items_order_id_index` (server migration version `20261123184005`).
- A read-only SQL audit confirmed the index definition and the existing unique buyer/request index. QA still has two existing Auth users and two profiles; products, carts, orders, and order_items remain at zero rows.
- Updated the disposable PostgreSQL 16 CI workflow to apply this migration and the integration SQL to assert the index exists. Static checks passed, and final-branch workflow run [45240917700](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/45240917700) completed successfully, including PostgreSQL integration and concurrency/cart-snapshot tests.
- Supabase Performance Advisor now reports six unindexed foreign keys rather than seven; `order_items_order_id` is no longer among them. It also reports the new index as unused because the QA table is empty. Do not remove the index on that basis; validate with representative data/workload before any tuning decision. Other existing performance notices include six multiple-permissive-policy groups. Leaked-password protection remains disabled and was not changed.
- A fresh read-only production audit on 2026-11-24 still found no `orders.request_id`, only `create_cod_order(text,text,text)`, direct authenticated INSERT privileges on `orders` and `order_items`, and broad anon/authenticated grants on `public.reports` including TRUNCATE, REFERENCES, and TRIGGER. Production was not changed.
- Verification boundary remains unchanged: CI is a disposable PostgreSQL 16 environment; QA transaction tests use the separate Supabase PostgreSQL 17.12 database with simulated JWT claims and `SET ROLE authenticated`. Real Supabase Auth HTTP, PostgREST HTTP RPC, and signed-in browser checkout remain unverified.
- No merge, production migration, deployment, backup/restore, or persistent test-data creation was performed. Existing backups and prior branch changes were preserved.
