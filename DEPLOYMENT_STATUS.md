# Deployment status

## Completed and verified

- Dedicated repository: `https://github.com/eei852552-rgb/nexora-market-production`. NEXUS AUTODEV and unrelated repositories were not modified.
- Supabase project `nexora-market` (`nbhfdiiehukdtusxksni`) is active and healthy. The live database has RLS enabled on marketplace tables.
- Auth/cart/COD migration, seller/admin controls, and launch security hardening migrations are applied. Seller applications, approved-seller product CRUD, advertising drafts, admin-only moderation, and seller-readable commission records are now represented in the database with RLS. Anonymous table grants were removed except for public published products/reviews/approved ads; unnecessary authenticated DDL-like privileges were reduced; product/ad input constraints and an admin-only ad status guard were added.
- Auth UI supports sign-up, sign-in, sign-out, email-confirmation messaging, password-reset request, recovery-link password update, local session persistence, refresh-token handling, and user-friendly errors.
- Live mode reads only published products. The live catalog currently has zero published products and correctly renders an empty state. Demo products are explicitly separated and cannot create a real cart or fake successful order.
- SEO/PWA/accessibility hardening added: exact NEXORA MARKET brand label, SVG favicon, web manifest, canonical/description metadata, robots.txt, sitemap.xml, and a root `manus-routes.json` route manifest.
- Burmese/English shell switching was verified in the browser after adding translated navigation, live-empty, demo, hero, and anonymous-safety copy. Static asset URLs now carry a release query string to reduce stale GitHub Pages client caches.
- Added `LAUNCH_DISCLOSURES.md` and a website footer disclosure panel for privacy, terms, seller rules, delivery/returns, contact status, and controlled-launch status. Missing business details are explicitly marked as not configured; no legal or operational promises were invented.
- Added `QA_PROCEDURE.md` with a non-secret, owner-controlled procedure for one confirmed QA account, least-privileged moderator assignment, seller approval, draft/publication, cart/COD, isolation, inventory, commission, and ad checks. No QA account, admin role, product, or order was created automatically.
- Local fresh server test on port 3011 passed: `/health` 200, route manifest JSON, static assets 200, and JavaScript syntax checks passed.
- Anonymous REST checks confirmed public product/ad reads work, private seller/application/commission/admin reads return HTTP 401, anonymous writes return HTTP 401, anonymous COD execution is not granted, and invalid login returns HTTP 400.
- Password reset UI was browser-tested. Auth signup reached Supabase but a disposable QA request returned HTTP 429 `email rate limit exceeded`; no repeated account creation was attempted.

## Live deployment

The verified production URL is https://eei852552-rgb.github.io/nexora-market-production/. Application release commit `32744e3` deployed successfully in run `39407436392`; the follow-up disclosure/QA documentation commit `0cb966f` deployed successfully in run `39407682336`. The live URL was opened in the browser with the cache-busted release query, the live empty-catalog state and disclosure footer loaded, and the privacy launch note opened successfully. HTTP checks for the HTML, versioned JavaScript assets, disclosure document, favicon, manifest, robots, sitemap, and root route manifest all returned 200.

## Exact remaining blockers

Supabase security advisors report one warning: `auth_leaked_password_protection` — leaked password protection is disabled. The project organization is on the Free plan, and official Supabase documentation says this feature is available on Pro and above. The current Supabase MCP exposes migrations and advisors but not Auth security-setting writes, so enabling it needs an eligible plan plus Owner/Administrator Dashboard or Management API permission. This is a security hardening item, not a reason to weaken Auth or bypass rate limits. Evidence and the exact manual path are recorded in `SUPABASE_AUTH_SECURITY.md`.

A confirmed user session is still unavailable for a real signed-in cart/order end-to-end test because Auth email signup is rate-limited. The source and RLS paths are implemented, but that test remains explicitly unverified. There are currently no published products, so live checkout cannot be exercised with a real listing.

Online payments remain disabled and no paid service or domain was purchased.


## COD idempotency QA status — re-audited 2026-11-22

- COD implementation baseline remains commit `3910fae39b3e3d7d2c2cb8d93a0ee7e5b8809e15`; subsequent commits refreshed QA status and deployment documentation only. The feature branch remains ahead of `main` and unmerged. No merge, main-branch update, or production deployment was performed.
- GitHub Actions run [44936615100](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44936615100) passed on the documentation-refresh branch tip `9f6cc650e8c000b2dc1cb0644cd8a90778c684d5`. Both `static-checks` and `postgres-integration` jobs passed, including JavaScript syntax, migration invariants, disposable PostgreSQL 16 integration checks, and two-session concurrency/cart-snapshot checks. The implementation-specific run [44795228889](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44795228889) also passed on the COD code baseline. These are CI/QA checks, not production verification.
- The separate Supabase project `nexora-market-qa` (`gudvguwhqhuvpblwdcil`) is active on PostgreSQL 17.12. Its migration history includes the COD idempotency migration and product stock-guard alignment. The production project remains `nexora-market` (`nbhfdiiehukdtusxksni`).
- A fresh read-only audit verified RLS is enabled on all nine QA public tables. Anon/authenticated have no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privileges on those tables. COD `orders` and `order_items` are SELECT-only for authenticated users; carts retain authenticated CRUD; public catalog reads remain available. This confirms the current table-level QA ACL hardening is in effect.
- Important remaining QA ACL issue: the `supabase_admin` default ACL for future public tables still grants broad privileges to anon/authenticated. The connected SQL role cannot alter defaults owned by `supabase_admin`; this requires owner-level review before creating additional public tables. The `postgres` default ACL is hardened.
- QA data is clean: `auth.users=2` and `profiles=2` are pre-existing records; `admin_roles`, `advertisements`, `carts`, `order_items`, `orders`, `products`, `seller_applications`, and `wishlists` each contain zero rows. No new persistent QA user, seller role, product, cart, or order was created in this run.
- A read-only SQL role simulation passed: anon can read the public product table but cannot read orders or insert orders/items; authenticated with a simulated JWT subject can read its own profile, select orders/items, execute the four-argument COD RPC, and use the private schema, while direct order/item INSERT remains denied. This tests PostgreSQL grants/RLS with simulated claims; it is not a real Supabase Auth session or HTTP request.
- The available QA PostgREST log window contained 14 requests, all to `/`; there were zero `create_cod_order` mentions and zero direct `/rest/v1/orders` paths. Therefore no actual PostgREST COD request or signed-in browser checkout has been verified.
- Supabase QA Security Advisor still reports `auth_leaked_password_protection` disabled. Performance Advisor reports 7 unindexed foreign keys and 6 multiple-permissive-policy findings. These were reviewed and not changed in this run.
- A fresh production read-only audit confirms `orders.request_id` is absent and only the legacy three-argument `public.create_cod_order(text,text,text)` exists. Authenticated users still have direct INSERT grants on production `orders` and `order_items`. Production `public.reports` has RLS enabled but anon/authenticated retain broad table privileges including INSERT, DELETE, TRUNCATE, REFERENCES, and TRIGGER; it currently has zero rows. These are separate production security blockers and were not modified.
- Production database, live GitHub Pages site, `main`, existing backups, and unrelated repositories were not changed. No backup/restore operation was run.

## Next safe gates

1. Obtain an owner-approved QA sign-in/session path and verify the four-argument COD RPC through actual Supabase Auth + PostgREST; do not create repeated accounts or bypass Auth rate limits.
2. Resolve the `supabase_admin` future-table default ACL with an owner-authorized procedure.
3. Review the unrelated production `reports` grants separately.
4. Re-review the complete candidate migration against the current production schema and a verified recoverable backup before any production change.
5. Keep the COD candidate off `main` and do not deploy or migrate production without explicit approval.


## COD idempotency transaction re-test — 2026-11-23

- Re-ran a disposable, transaction-scoped checkout test directly against the separate Supabase QA project `nexora-market-qa` (PostgreSQL 17.12). The entire test, including temporary fixture creation, was enclosed in one transaction and explicitly rolled back.
- The first authenticated-role RPC call created one COD order with a database-calculated total of 2,500 MMK. Repeating the same buyer/request UUID returned the exact same order ID with `idempotent_replay=true`; stock was decremented once only.
- Added a new cart item after the first order, then replayed the original request. The replay returned the original order and did not consume the new cart row.
- Tested an atomic failure after an earlier valid cart line: a later low-stock line raised `insufficient stock`; the earlier line's order-item insert, stock decrement, and cart deletion were all rolled back. The two cart rows remained and the other product stocks remained unchanged.
- RLS visibility assertions passed in the same QA transaction: the buyer saw one order/item, an unrelated temporary buyer saw zero, and the seller associated with the item saw one. All assertions passed.
- Post-rollback read-only audit confirmed `auth.users=2`, `profiles=2`, `admin_roles=0`, and zero rows in products, carts, orders, order_items, and the other marketplace tables. The temporary third Auth user, temporary admin role, products, cart rows, order, and order item did not persist.
- This was a real Supabase QA PostgreSQL transaction using `SET ROLE authenticated` and simulated JWT subject claims. It is stronger than a local fixture but is **not** a real Supabase Auth HTTP session, PostgREST HTTP RPC, or signed-in browser checkout. Those remain unverified.
- Current feature branch tip is `bfff245aa286fe9ecde71f09cc30f49a4cf5c3cd`. The four commits after tested implementation baseline `3910fae39b3e3d7d2c2cb8d93a0ee7e5b8809e15` changed only `COD_CHECKOUT_RETRY_QA.md`, `DEPLOYMENT_STATUS.md`, and `docs/cod-checkout-deployment-runbook.md`; no application or migration code changed. The latest passing CI run remains [44936615100](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/44936615100) on code-equivalent commit `9f6cc650e8c000b2dc1cb0644cd8a90778c684d5`.
- A fresh production read-only audit still finds no `orders.request_id`, only the legacy three-argument COD RPC, direct authenticated INSERT grants on orders/items, and broad anon/authenticated grants on `public.reports` (including TRUNCATE, REFERENCES, and TRIGGER). No production object or data was changed.
- No merge, live deployment, backup/restore, or production migration was performed. Existing backups and all prior feature-branch changes were preserved.


## COD QA update — 2026-11-24

- QA-only additive migration `202611240001_cod_order_items_order_id_index.sql` applied to the separate `nexora-market-qa` project; read-only audit confirms `order_items_order_id_idx` and the buyer/request unique index.
- QA data remains clean: 2 existing Auth users, 2 profiles, and zero products, carts, orders, or order items.
- CI now applies the new index migration to its disposable PostgreSQL 16 database and asserts the index exists. Final branch CI run [45240917700](https://github.com/eei852552-rgb/nexora-market-production/actions/runs/45240917700) passed static checks, PostgreSQL integration, and concurrency/cart-snapshot checks.
- Performance Advisor's unindexed-FK count decreased from 7 to 6. It marks the new index unused because the QA table is empty; representative workload validation is still required. Leaked-password protection remains disabled.
- Production read-only audit on 2026-11-24 confirms it is still on the legacy three-argument COD function, has no `orders.request_id`, allows authenticated direct INSERT on orders/items, and retains broad grants on `public.reports`. No production change was made.
- Real Supabase Auth HTTP, PostgREST RPC, and browser checkout remain unverified. No merge, deployment, production migration, backup/restore, or persistent QA fixture was performed.
- Main remains at `2da8087db864d58cd9dc3de17e1dc0f6d49b3ca0`; QA branch code/test commit for this verification is `4782f4adadac961907ae1afd98937c0035bff249`. Existing backups and earlier branch changes are preserved.
