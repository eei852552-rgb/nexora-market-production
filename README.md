# NEXORA MARKET

NEXORA MARKET is a mobile-first Myanmar/English marketplace with a live Supabase mode and a clearly separated demo preview. The live mode uses browser-safe Supabase Auth, published product reads, RLS-protected carts and wishlists, session refresh, buyer order history, and an atomic cash-on-delivery order RPC. Online payments remain disabled.

## Run locally

```bash
npm start
```

Open `http://localhost:3001`. The browser build uses only the Supabase project URL and publishable key from `config.js`; no service-role key or session token is committed to frontend source.

## Live, demo, and seller modes

Live mode is the default. It loads only `products.status = 'published'` from the authorized Supabase project. If there are no published listings, it shows an empty live catalog rather than silently showing fake products. **Open demo preview** explicitly switches to the labeled in-memory catalog; demo cart actions never create a real cart or successful order.

Signed-in users can apply to become sellers. Database RLS requires an approved seller application before product drafts or advertising drafts can be created. Product drafts remain unpublished until a verified admin/moderator publishes them. Admin applications, product moderation, advertising review, and commission records are protected by database-side authorization; the frontend never grants itself a role.

## Auth and persistence

Sign up, sign in, sign out, email-confirmation messaging, password-reset request, recovery-link password update, local session persistence, and refresh-token handling are implemented through Supabase Auth REST endpoints. Signed-in users can persist carts and wishlists through RLS. COD checkout calls `create_cod_order`, which validates delivery details, reads the user's cart, validates product availability and prices, uses the existing stock/total triggers, clears the cart only after success, and returns an error without a success message when the database rejects the order.

The database migrations are recorded in `supabase/auth-cart-cod.sql`, `supabase/production-hardening.sql`, `supabase/seller-admin-controls.sql`, and `supabase/launch-security-hardening.sql`. The launch hardening migration removes anonymous table grants, limits authenticated table privileges to the operations the app needs, validates MMK prices/stock/categories/descriptions/HTTPS images, and prevents sellers from self-approving advertising records.

## Security and known configuration item

The frontend never trusts a role flag for authorization. Database RLS/triggers enforce ownership, product status, stock, price, order ownership, seller approval, ad review, commission visibility, and COD RPC access. Supabase security advisors currently report one external Auth warning: **Leaked Password Protection is disabled**. Enabling it requires the Supabase Auth dashboard/management permission, which is not exposed by the current authorized MCP tools. It should be enabled before production account onboarding: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## GitHub Pages

`.github/workflows/pages.yml` deploys the static website on pushes to `main`. The dedicated repository is `https://github.com/eei852552-rgb/nexora-market-production`, and the verified live URL is `https://eei852552-rgb.github.io/nexora-market-production/`. SEO metadata, favicon, `robots.txt`, `sitemap.xml`, PWA manifest, and the root route manifest are included.

## Payments

Online payments are intentionally disabled. The app collects no card details and does not claim a payment succeeded. A Myanmar-compatible provider must be selected, configured, and tested before adding payment UI.

## Launch disclosures

`LAUNCH_DISCLOSURES.md` contains the current non-legal launch draft for privacy, terms, seller rules, delivery/returns, contact status, and controlled-launch disclosures. The website footer exposes the same notes. It intentionally states which business details are not configured instead of inventing an email, delivery promise, return policy, or legal claim.

`QA_PROCEDURE.md` contains the safe confirmed-account test sequence and owner-controlled moderator setup. It does not create users, test fixtures, or admin roles automatically.
