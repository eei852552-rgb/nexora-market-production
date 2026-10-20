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

Supabase security advisors report one warning: `auth_leaked_password_protection` — leaked password protection is disabled. The current Supabase MCP exposes migrations and advisors but not Auth security-setting writes, so enabling it needs Supabase dashboard/management permission. This is a security hardening item, not a reason to weaken Auth or bypass rate limits.

A confirmed user session is still unavailable for a real signed-in cart/order end-to-end test because Auth email signup is rate-limited. The source and RLS paths are implemented, but that test remains explicitly unverified. There are currently no published products, so live checkout cannot be exercised with a real listing.

Online payments remain disabled and no paid service or domain was purchased.
