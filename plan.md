# NEXORA MARKET Plan

NEXORA MARKET is a new standalone marketplace project and does not modify the previous NEXUS AUTODEV project. The first working version uses a dependency-light responsive frontend plus a tiny static server so an Android beginner can preview it easily. It includes a local demo session model, buyer shopping flows, cash-on-delivery checkout, seller dashboard, admin moderation views, bilingual UI, and clearly labeled demo data. Private data is not persisted until Supabase Auth and the supplied schema are configured.

The visual direction is a premium orbital marketplace: deep navy surfaces, electric blue and violet accents, generous rounded cards, compact status labels, and high-contrast touch targets. Navigation is a mobile-first command dock rather than a dense desktop-only sidebar.

Project structure: `index.html` is the shell; `styles.css` is the design system; `app.js` owns demo state and views; `server.js` serves the app and health endpoint; `supabase/schema.sql` contains authenticated tables and RLS policies; `README.md` contains beginner deployment steps.
