# NEXORA MARKET

NEXORA MARKET is a mobile-first marketplace frontend with a clearly separated demo preview and a live Supabase-backed mode. The live mode now uses browser-safe Supabase Auth, published product reads, RLS-protected cart/wishlist persistence, session storage/refresh, real order history, and an atomic cash-on-delivery order RPC. Online payments remain disabled.

## Run locally

```bash
npm start
```

Open `http://localhost:3001`. The browser build uses only the Supabase project URL and publishable key from `config.js`; no service-role key is shipped to the browser.

## Live mode and demo mode

Live mode is the default. It loads only `products.status = 'published'` from the authorized Supabase project. If there are no published listings, it shows an empty live catalog rather than silently showing fake products. The **Open demo preview** button explicitly switches to the labeled in-memory catalog. Demo cart actions never create a real cart or successful order.

## Auth and persistence

Sign up, sign in, sign out, session persistence, and token refresh are implemented through Supabase Auth REST endpoints. Signed-in users can persist carts and wishlists through RLS-protected tables. COD checkout calls `create_cod_order`, which validates delivery details, reads the user's cart, validates product availability and prices, uses the existing stock/total triggers, clears the cart only after success, and returns an error without a success message when the database rejects the order.

The database migrations are recorded in `supabase/auth-cart-cod.sql` and `supabase/production-hardening.sql`. The live database currently has no published products, so product loading correctly returns an empty live catalog.

## Security boundary

The frontend never trusts a role flag for authorization. Admin access is read from the protected `admin_roles` table, and database RLS/triggers enforce ownership, product status, stock, price, order ownership, and COD RPC access. Keep the service-role key server-side; it is not present in this repository or browser code.

## GitHub Pages

`.github/workflows/pages.yml` deploys the static website on pushes to `main`. The dedicated repository is `https://github.com/eei852552-rgb/nexora-market-production`. The Node server is only for local/preview use; GitHub Pages serves the static files directly.

## Payments

Online payments are intentionally disabled. The app collects no card details and does not claim a payment succeeded. A Myanmar-compatible provider must be selected, configured, and tested before adding payment UI.
