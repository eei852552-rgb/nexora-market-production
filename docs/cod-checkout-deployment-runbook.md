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
