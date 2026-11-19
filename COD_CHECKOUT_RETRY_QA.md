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
- The QA project currently has broad default table grants on its public tables, including `TRUNCATE` on COD-related tables. RLS does not block `TRUNCATE`. Do not use this project for browser/authenticated QA or create fixtures until an owner reviews and applies `scripts/qa-project-acl-hardening.sql`, then verifies the resulting grants.
- The CI workflow uses a disposable PostgreSQL 16 service. Its tests are local/CI database tests, not proof of Supabase Auth/PostgREST behavior or production verification.
- No QA account, seller role, product, cart, or order has been created in the Supabase QA project. Production data and the live deployment remain untouched.
