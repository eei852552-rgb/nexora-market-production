# COD checkout retry-safety QA

This change is prepared on branch `cod-idempotency-qa-20261119`. The migration is **not applied to the live Supabase project**, and the GitHub Pages workflow deploys only `main`.

## Required QA environment

- Use a separate Supabase QA project with the same current marketplace schema and triggers.
- Apply `supabase/migrations/202611190001_cod_checkout_idempotency.sql` to that QA project only.
- Use one owner-confirmed QA buyer and QA-only published product fixtures.
- Do not create test orders, test accounts, or fake listings in production.

## Acceptance tests

1. Add one QA product to the buyer cart and submit a COD checkout with a new request UUID. Confirm exactly one order and matching order items are created, the database-calculated total is returned, stock is reduced once, and only the consumed cart rows are removed.
2. Repeat the exact RPC call with the same buyer and request UUID after the cart is empty. Confirm the same order ID and total are returned, with no second order, no second stock decrement, and no extra order items.
3. Simulate a lost client response after the server commits, then retry using the same request UUID. Confirm the original order is returned.
4. Run two concurrent requests with the same buyer and request UUID. Confirm both responses resolve to the same order ID and stock is reduced only once.
5. While checkout is waiting on cart-row locks, attempt to add/update another cart row from a second session. Confirm the later cart change is not deleted by the first checkout.
6. Attempt direct authenticated INSERTs into `orders` and `order_items`. Confirm they are denied and that the authenticated buyer can create an order only through the guarded RPC.
7. Try a missing request UUID, empty cart, invalid delivery fields, unavailable product, and insufficient stock. Confirm each request fails atomically: no partial order, no partial order items, no stock decrement, and no cart loss.
8. Confirm a different buyer cannot retrieve or replay another buyer's request UUID/order.

## Production gate

Do not apply this migration to the production Supabase project or deploy this branch until QA passes, the migration is reviewed against the live schema, and the project owner explicitly approves the production change. The main branch and current live deployment remain unchanged by this branch.


## Current environment and verification boundary

- The feature branch's `config.js` points to the separate Supabase project `nexora-market-qa`; it is not the production project.
- A read-only Supabase audit confirmed the QA project is active, has the COD request-ID column and unique index, and has the four-argument public RPC plus private implementation/RLS helpers. Current counts: `auth.users=2` and `profiles=2` (pre-existing); `admin_roles`, `advertisements`, `carts`, `order_items`, `orders`, `products`, `seller_applications`, and `wishlists` each contain zero rows.
- The nine current QA public tables have been hardened by `scripts/qa-project-acl-hardening.sql`: anon/authenticated have no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges; COD orders/items are SELECT-only for authenticated users; carts retain CRUD; and catalog reads remain available. The `postgres` owner's future-table defaults are also revoked for anon/authenticated. The `supabase_admin` default ACL remains broad because the connected SQL role cannot alter defaults owned by that role; owner-level review is still required before creating new public tables under `supabase_admin`.
- The CI workflow uses a disposable PostgreSQL 16 service. Its tests are local/CI database tests, not proof of Supabase Auth/PostgREST behavior or production verification.
- No new persistent QA accounts, seller roles, products, carts, or orders were created. Two pre-existing Auth user records were preserved. Transaction-scoped test fixtures were rolled back and left no rows behind. Production data and the live deployment remain untouched.


## QA product stock-guard alignment

- Read-only inspection found that the QA project's `nexora_product_guard()` had an extra `private.is_approved_seller()` check on every product update. The order-item SECURITY DEFINER trigger decrements stock while the JWT subject is the buyer, so this QA-only check blocked otherwise valid COD checkout.
- Migration `202611210001_product_stock_guard_alignment.sql` aligns the guard with the production hardening definition. Seller approval remains enforced by the product INSERT/UPDATE RLS policies; the trigger no longer rejects the internal stock decrement because the buyer is not a seller.
- Applied to `nexora-market-qa` as migration `product_stock_guard_alignment` (version `20261120183734`); the `products_guard` trigger remains attached and now uses the aligned function.
- The disposable PostgreSQL fixture now starts with the QA-only guard and applies this migration before tests. The normal COD stock-decrement assertion therefore fails if the alignment migration is missing.

## Latest CI evidence

- [Latest GitHub Actions run 44795228889](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44795228889) passed on commit `3910fae39b3e3d7d2c2cb8d93a0ee7e5b8809e15`; both static checks and PostgreSQL integration/concurrency jobs passed.
- The disposable PostgreSQL 16 run applies the COD idempotency migration, COD ACL migration, and product stock-guard alignment migration. It passes retry/replay, least-privilege ACL, RLS isolation, invalid-input, missing-request-ID, insufficient-stock rollback, unavailable-product rollback, buyer-scoped request-ID, concurrent same-request, and concurrent cart-snapshot checks.
- A separate transaction-scoped test against the actual Supabase QA PostgreSQL 17.12 project passed: first COD order and replay returned one order ID; total was 2,500 MMK; stock moved from 10 to 8 once; the original cart row was consumed; another buyer saw zero order/items while the seller saw one; direct INSERTs into orders/items were denied; insufficient stock, invalid delivery, and missing request ID failed without partial order/stock/cart effects.
- That QA test used temporary Auth user/product fixtures inside one transaction and rolled back. The pre-existing Auth user count remained 2; the two pre-existing profile rows remained, while the other eight public tables remained empty.
- The QA SQL test uses simulated JWT claim settings and database role switching. It verifies the QA database functions, triggers, grants, and RLS, but does not verify the Supabase Auth HTTP API, PostgREST HTTP behavior, or a signed-in browser session. It is not production verification.


## Re-audit — 2026-11-22

- A fresh read-only audit confirmed RLS is enabled on all nine QA public tables and anon/authenticated have no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges. Authenticated `orders` and `order_items` are SELECT-only; carts retain CRUD; public catalog reads remain available.
- The `supabase_admin` default ACL for future public tables remains broad for anon/authenticated. The connected SQL role cannot change that owner-level default. Do not create additional public tables until an owner-authorized fix is reviewed.
- Read-only role simulation passed: anon can read published products but cannot read orders or insert orders/items; authenticated with a simulated JWT subject can read its own profile and select orders/items, while direct INSERT into orders/items is denied and the COD RPC is executable. This is database role/RLS simulation, not an actual Supabase Auth session or PostgREST request.
- The available PostgREST log window showed 14 requests, all to `/`, with no `create_cod_order` mention and no `/rest/v1/orders` path. Actual Auth + PostgREST COD verification and signed-in browser checkout remain outstanding.
- QA Security Advisor still reports leaked-password protection disabled. Performance Advisor reports 7 unindexed foreign keys and 6 multiple-permissive-policy findings.
- Production re-audit: `orders.request_id` is absent; only the legacy three-argument COD RPC exists; authenticated direct INSERT grants remain on orders/items; and `public.reports` has RLS enabled but broad anon/authenticated table privileges including TRUNCATE. No production changes were made.

## Repeat Supabase QA transaction — 2026-11-25

- Reconfirmed the separate QA project `nexora-market-qa` is `ACTIVE_HEALTHY` on PostgreSQL 17.12. The production project remains separate.
- Re-ran a fresh transaction-scoped COD test using only the two pre-existing QA Auth users. No new Auth account was created.
- The first buyer's COD request created one order with a database-calculated total of 2,500 MMK. Repeating the same buyer/request UUID returned the same order ID with `idempotent_replay=true`; stock changed from 10 to 8 only once.
- Added a new cart row after the first successful checkout, then replayed the original request. The replay preserved that newer cart row and did not decrement stock again.
- Reused the same request UUID as the second buyer. A distinct order was created, confirming idempotency is scoped to `(buyer_id, request_id)`; stock changed from 8 to 7 once for that second buyer.
- Tested atomic rollback with two cart lines ordered so a valid-stock line was processed before a later insufficient-stock line. The failure left no order or order items for that request, restored the earlier stock decrement, and preserved both cart rows.
- Direct authenticated INSERT attempts into `orders` and `order_items` were denied.
- RLS checks passed: the first buyer saw only their own order/items and cart; the second account (also the product seller) saw its own order plus the relevant seller order/items, but no buyer carts.
- The complete fixture test ran inside an explicit transaction and ended with `ROLLBACK`. A subsequent read-only audit confirmed `auth.users=2`, `profiles=2`, `admin_roles=0`, and zero rows in products, carts, orders, order_items, advertisements, seller_applications, and wishlists. Both COD indexes remain present.
- The test uses simulated JWT subject claims and database role switching. It validates the QA PostgreSQL functions, triggers, grants, and RLS; it is **not** a real Supabase Auth HTTP login, PostgREST HTTP RPC, or signed-in browser checkout.
- A source review confirms the browser keeps one unresolved request UUID per buyer in session storage. It retains the key when the RPC or post-order account refresh fails, and clears it only after the refresh succeeds; this preserves safe retry behavior. This is a code review, not a browser end-to-end test.
- The current branch tip is `d2527ff14f99d898bd570dea09270411f6abf314`. Compared with the last passing code/test commit `4782f4adadac961907ae1afd98937c0035bff249`, the two intervening commits changed documentation only. The latest passing CI run remains [45240917700](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/45240917700) on the code/test commit; it is a disposable PostgreSQL 16 CI run, not Supabase Auth/PostgREST or production verification.
- Remaining QA blockers: `supabase_admin` future-table defaults still grant broad privileges to anon/authenticated and require an owner-authorized fix; leaked-password protection remains disabled; real Auth/PostgREST/browser verification is still outstanding.
- Production read-only verification still finds no `orders.request_id`, only the legacy three-argument COD RPC, authenticated direct INSERT grants on orders/items, and 14 broad anon/authenticated grants on `public.reports` (including DDL-like table privileges). No production object or row was changed.
- No merge, deployment, production migration, backup/restore, or persistent QA fixture was performed. Existing branch changes and backups remain preserved.
