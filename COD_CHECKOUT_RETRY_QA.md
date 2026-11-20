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
- A read-only Supabase audit confirmed the QA project is active, has the COD request-ID column and unique index, and has the four-argument public RPC plus private implementation/RLS helpers. Its current orders, order items, carts, products, and profiles tables contain zero rows.
- The nine current QA public tables have been hardened by `scripts/qa-project-acl-hardening.sql`: anon/authenticated have no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges; COD orders/items are SELECT-only for authenticated users; carts retain CRUD; and catalog reads remain available. The `postgres` owner's future-table defaults are also revoked for anon/authenticated. The `supabase_admin` default ACL remains broad because the connected SQL role cannot alter defaults owned by that role; owner-level review is still required before creating new public tables under `supabase_admin`.
- The CI workflow uses a disposable PostgreSQL 16 service. Its tests are local/CI database tests, not proof of Supabase Auth/PostgREST behavior or production verification.
- No new persistent QA accounts, seller roles, products, carts, or orders were created. Two pre-existing Auth user records were preserved. Transaction-scoped test fixtures were rolled back and left no rows behind. Production data and the live deployment remain untouched.


## QA product stock-guard alignment

- Read-only inspection found that the QA project's `nexora_product_guard()` had an extra `private.is_approved_seller()` check on every product update. The order-item SECURITY DEFINER trigger decrements stock while the JWT subject is the buyer, so this QA-only check blocked otherwise valid COD checkout.
- Migration `202611210001_product_stock_guard_alignment.sql` aligns the guard with the production hardening definition. Seller approval remains enforced by the product INSERT/UPDATE RLS policies; the trigger no longer rejects the internal stock decrement because the buyer is not a seller.
- The disposable PostgreSQL fixture now starts with the QA-only guard and applies this migration before tests. The normal COD stock-decrement assertion therefore fails if the alignment migration is missing.

## Latest CI evidence

- [GitHub Actions run 44592086326](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44592086326) passed on commit `d7b98700ba38eb11861213c0f9c18bc0589b4dde`.
- The disposable PostgreSQL 16 run applied both COD migrations and passed retry/replay, least-privilege ACL, RLS isolation, invalid-input, missing-request-ID, insufficient-stock rollback, unavailable-product rollback, and buyer-scoped request-ID checks.
- Two concurrent same-request checkout calls returned the same order; stock was reduced once; a different cart row added while checkout waited remained in the cart.
- This does not verify Supabase Auth, PostgREST, a signed-in browser session, or production behavior.
