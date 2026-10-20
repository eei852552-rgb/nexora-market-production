# Deployment status

## Completed

- Local NEXORA MARKET demo runs on port 3001 and has passed browser checks for buyer checkout/order history, seller hub, admin console, and `/health`.
- A backup was created before the deployment changes: `/home/ubuntu/nexora-market-backup-20261020-085710.tar.gz`.
- Supabase project `nexora-market` (`nbhfdiiehukdtusxksni`) is active and healthy, has RLS-enabled marketplace tables, and security advisors returned no lints.
- Migration `harden_product_moderation_and_order_integrity` was applied successfully. It protects product moderation status, forces authenticated ownership for orders, validates published product/price/stock for order items, decrements stock transactionally, recalculates totals, and adds seller order visibility.
- The current source was pushed to a new public repository so the older `nexora-market` repository was not modified: https://github.com/eei852552-rgb/nexora-market-production
- GitHub Actions workflow is included at `.github/workflows/pages.yml`.

## Blocker

GitHub Pages is not enabled because the available GitHub integration token is allowed to push code but is not allowed to create a Pages site. The workflow was run twice and failed at `configure-pages` with GitHub `Resource not accessible by integration` (403). The candidate Pages URL was tested and correctly returned GitHub's 404 because the Pages site does not exist yet.

This means there is no verified production URL yet. The temporary Manus forwarding preview remains the only verified public preview and is not a durable production deployment.

## Honest product status

The browser UI remains a clearly labeled demo/prototype: real Supabase persistence/authentication is not connected to the frontend, and online payments are disabled. No card data is collected. Do not present demo orders, sellers, reviews, or metrics as real customer data.
