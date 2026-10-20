# Deployment status

## Completed

- Backup before Auth/database changes: `/home/ubuntu/nexora-market-auth-backup-20261020-092914.tar.gz`.
- Supabase project `nexora-market` (`nbhfdiiehukdtusxksni`) is active and healthy. RLS is enabled on the marketplace tables and the security advisor currently returns no lints.
- `add_auth_cart_and_cod_checkout` was applied. It added owner-only `carts` and `wishlists`, automatic profile creation after Auth signup, a cart-required order insert policy, and the `create_cod_order` database RPC.
- Browser-safe Supabase configuration and REST client were added. Only the project URL and publishable key are used in browser code; no service-role key is present.
- Auth UI supports sign-up, sign-in, sign-out, local session persistence, refresh-token handling, and error display.
- Live mode loads only published products from Supabase. The live catalog currently has zero published products and correctly renders an empty state.
- Live cart/wishlist/order-history flows are protected by sign-in and RLS. Demo mode is explicit and cannot create a real cart or fake successful order.
- Anonymous `create_cod_order` access was tested and returned HTTP 401. Anonymous cart reads returned HTTP 200 with no rows, consistent with RLS. Invalid login returned HTTP 400. The live database connection, Auth modal, live empty state, and demo separation were browser-tested.
- Updated source was committed as `d120b17` and pushed to the dedicated repository.
- GitHub Actions Pages workflow completed successfully for `d120b17`.
- Live website was opened and verified at: https://eei852552-rgb.github.io/nexora-market-production/

## Test limitation

A disposable Auth signup test reached Supabase but returned HTTP 429 `email rate limit exceeded`; no verified QA session was available to complete a real signed-in cart/order browser test. The frontend handles this error without claiming signup success. A real confirmed test account or a later Auth email-rate-limit window is required for that final end-to-end test.

## Honest product status

Real Auth and database integration is implemented in source and the database migration is applied, but no real published products or verified QA account currently exist. Online payments remain disabled. Demo sellers, ratings, orders, and metrics are not real customer data.

The older `nexora-market` repository and NEXUS AUTODEV were not modified.
