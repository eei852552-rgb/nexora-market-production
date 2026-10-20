# NEXORA MARKET TODO

- [x] Build responsive Myanmar/English marketplace navigation, search, categories, product details, loading/error/empty states, and mobile touch layout.
- [x] Keep demo products, demo cart behavior, and demo screens explicitly separated from live data; demo actions cannot create real orders.
- [x] Apply Supabase RLS/hardening for product moderation, stock, price, order ownership, carts, wishlists, and COD checkout.
- [x] Add browser-safe Supabase Auth with sign-up, sign-in, sign-out, email-confirmation messaging, password-reset request/recovery update, session persistence, refresh handling, and errors.
- [x] Add seller application workflow, approved-seller product draft creation, advertising draft controls, admin application/product moderation, and commission visibility policies enforced by database authorization.
- [x] Remove anonymous table write/read grants for private data, reduce unnecessary authenticated table privileges, validate product/ad inputs, and prevent seller self-approval of ad status.
- [x] Verify Burmese/English shell switching and translate the navigation, empty live catalog, demo CTA, hero, and anonymous-safety copy.
- [x] Add published-product loading, persistent cart, persistent wishlist, order history, and database-backed COD creation.
- [x] Add favicon, PWA manifest, canonical metadata, robots.txt, sitemap.xml, accessible brand label, and root route manifest.
- [x] Verify anonymous isolation, live empty-catalog behavior, demo separation, local server assets/routes, syntax, and browser Auth/password-reset entry points.
- [ ] Complete signed-in cart/order browser test after Supabase email signup rate limit permits a confirmed QA account.
- [ ] Publish at least one authorized real product before calling the live catalog populated.
- [ ] Enable Supabase leaked-password protection through dashboard/management permission.
- [ ] Configure a Myanmar-compatible payment provider; online payments remain disabled.
