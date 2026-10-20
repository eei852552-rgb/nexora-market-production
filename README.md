# NEXORA MARKET

A new, mobile-first marketplace starter. The current version is a functioning demo with buyer shopping, wishlist, cart, cash-on-delivery checkout, order tracking, seller hub, admin moderation console, bilingual label switching, validation feedback, and clearly labeled demo data.

## Run locally

```bash
npm start
```

Open `http://localhost:3001`. On an Android phone, you can use the project files in Acode and its preview. No API key is required for the demo.

## What is not connected yet

The app is intentionally safe in demo mode. Supabase Auth/database is not connected until a Supabase project URL and browser-safe anon key are configured. The service-role key must never be placed in browser code. Online payments are disabled; the initial checkout only records a cash-on-delivery order in demo state. Do not claim real payment success until a provider is selected, configured, and tested for Myanmar.

## Optional Supabase setup

1. Create a Supabase project on the free tier.
2. Open SQL Editor and run `supabase/schema.sql`.
3. Enable Email or another suitable Auth provider.
4. Add only the project URL and anon key to a future browser-safe config file.
5. Keep the service-role key server-side and add server authorization before enabling private persistence.

## Cloudflare Pages

Upload this project or connect its repository and deploy the static files. The current `server.js` is for local preview only. Deployment is not performed automatically because no Cloudflare account authorization was supplied.

## Android manual steps

At this stage there are no required manual steps to preview the demo. For real accounts and persistence, configure Supabase as described above. For online payment, choose and verify a compliant provider first; no card fields are collected by this starter.
