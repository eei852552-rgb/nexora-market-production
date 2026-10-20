# Deployment status

## Completed

- Backup before Auth/database changes: `/home/ubuntu/nexora-market-auth-backup-20261020-092914.tar.gz`.
- Supabase project `nexora-market` (`nbhfdiiehukdtusxksni`) is active and healthy. RLS is enabled on the marketplace tables and the security advisor currently returns no lints.
- `add_auth_cart_and_cod_checkout` was applied. It added owner-only `carts` and `wishlists`, automatic profile creation after Auth signup, a cart-required order insert policy, and the `create_cod_order` database RPC.
- Browser-safe Supabase configuration and REST client were added. Only the project URL and publishable key are used in browser code; no service-role key is present.
- Auth UI now supports sign-up, sign-in, sign-out, local session persistence, refresh-token handling, and error display.
- Live mode loads only published products from Supabase. The current live catalog has zero published products and correctly renders an empty state.
- Live cart/wishlist/order-history flows are protected by sign-in and RLS. Demo mode is explicit and cannot create a real cart or fake successful order.
- COD RPC access control was tested anonymously: the endpoint returned HTTP 401. Anonymous cart reads returned HTTP 200 with no rows, consistent with RLS. Invalid login returned HTTP 400. Signup UI and live database connection were browser-tested.
- Updated code was syntax-checked and the temporary preview rendered live-mode empty state and separated demo mode.

## Test limitation

A disposable Auth signup test reached Supabase but returned HTTP 429 `email rate limit exceeded`; no verified QA session was available to complete a real signed-in cart/order integration test. The frontend handles this error without claiming signup success. A real confirmed test account or a later Auth email-rate-limit window is required for end-to-end authenticated browser testing.

## Deployment

The dedicated public repository is `https://github.com/eei852552-rgb/nexora-market-production`. The GitHub Actions Pages workflow is present and the repository's latest pre-integration workflow run was successful. After the Auth integration commit is pushed, the workflow must complete again and the GitHub Pages URL must be opened and checked before calling it deployed.

The older `nexora-market` repository and NEXUS AUTODEV were not modified.

## Honest product status

Real Auth and database integration is implemented in source and the database migration is applied, but no real published products or verified QA account currently exist. Online payments remain disabled. Demo sellers, ratings, orders, and metrics are not real customer data.
