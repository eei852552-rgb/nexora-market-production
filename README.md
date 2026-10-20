# NEXORA MARKET

A new, mobile-first marketplace starter. The current version is a functioning demo with buyer shopping, wishlist, cart, cash-on-delivery checkout, order tracking, seller hub, admin moderation console, bilingual label switching, validation feedback, and clearly labeled demo data.

## Run locally

```bash
npm start
```

Open `http://localhost:3001`. On an Android phone, you can use the project files in Acode and its preview. No API key is required for the demo.

## GitHub Pages deployment

The repository includes `.github/workflows/pages.yml`. After the repository's Pages source is set to **GitHub Actions**, every push to `main` deploys the static website automatically. The site does not require the Node server in production because GitHub Pages serves `index.html`, `styles.css`, `app.js`, and `public/` directly.

## Data and payments status

The UI is intentionally labeled demo mode. Supabase is available as an authorized project and the database schema/RLS foundation exists, but this static build does not claim real authentication or persistence until the client auth flow is connected and tested. Online payments are disabled; the initial checkout only demonstrates cash-on-delivery and never stores card details. Do not claim real payment success until a provider is selected, configured, and tested for Myanmar.

## Supabase setup

The authorized project is documented in `supabase/schema.sql` for a clean deployment. Keep the service-role key server-side. Only a publishable/anon key may appear in a browser build, and only with matching RLS policies. The existing Supabase project has healthy security advisors and RLS-enabled tables.

## Android manual steps

For the public preview, no manual step is needed after Pages finishes deploying. For real accounts and persistence, configure Supabase Auth and connect the tested client flow. For online payment, choose and verify a compliant provider first; no card fields are collected by this starter.
