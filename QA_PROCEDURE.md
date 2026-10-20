# NEXORA MARKET — Safe QA Procedure

This procedure is for an operator using a confirmed QA account. It must not be used to create disposable accounts repeatedly, bypass Auth limits, expose passwords, or seed fake customer/product/order data into live production.

## Preconditions

1. Enable Supabase Auth **Leaked Password Protection** in the project Dashboard.
2. Prefer a separate authorized QA Supabase project. If a separate project is unavailable, do not create a fabricated listing or order in the live project without explicit operator approval and a clearly labeled QA fixture.
3. Create one real QA account through the website with an operator-controlled email address. Confirm the email normally; do not use a bypass or service-role credential.
4. The project owner verifies the exact Auth user UUID in the Supabase Dashboard. Never identify an admin by email text alone and never paste a password into SQL, chat, Git, or frontend code.

## Controlled moderator setup

For a QA environment only, the project owner may assign the least-privileged moderation role after verifying the exact UUID:

```sql
insert into public.admin_roles (user_id, role)
values ('<EXACT_CONFIRMED_QA_USER_UUID>', 'moderator')
on conflict (user_id) do update set role = excluded.role;
```

Verify the row is for the intended UUID before running it. Do not grant `admin` to a casual tester. Remove the role after QA in the same owner-controlled session:

```sql
delete from public.admin_roles
where user_id = '<EXACT_CONFIRMED_QA_USER_UUID>';
```

## Test sequence

1. Open the deployed website and sign in with the confirmed QA account. Refresh the page and verify the session persists. Sign out and verify private views return to the sign-in gate.
2. In the buyer account, use only an explicitly labeled QA fixture in the QA environment. Add it to the cart, refresh, remove it, and confirm the cart belongs only to that account.
3. Create a seller application. Confirm the application is pending and that the account cannot create a product before approval.
4. As the verified moderator, approve the seller application. Confirm the seller can create a draft but cannot publish it directly.
5. Create a QA-only draft with valid MMK price, non-negative stock, a valid category/description, and an HTTPS image URL. Confirm invalid price, negative stock, oversized text, non-MMK currency, and non-HTTPS image URLs are rejected by the database.
6. As moderator, publish the draft. Confirm it becomes visible in the live catalog only after publication. Confirm an unapproved seller cannot publish by direct REST/PATCH requests.
7. As buyer, add the published QA fixture to the persistent cart and create a COD order with a valid delivery name, phone, and address. Confirm the returned total is database-calculated, the cart is cleared only after success, and stock is decremented atomically.
8. Attempt invalid COD details, excess quantity, stale price, and access to another buyer's orders. Confirm each request fails without a success message or data disclosure.
9. Verify seller order visibility is limited to order items belonging to that seller and buyer order history is limited to that buyer.
10. Verify commission reads are limited to the seller or moderator/admin and that sellers cannot write or approve commission records.
11. Verify advertisement creation starts as draft, seller status changes are ignored/rejected, and only moderator/admin actions can approve or pause an advertisement.
12. Archive/delete only QA fixtures according to the QA project's cleanup policy. Do not delete real customer records from the live project.

## Evidence to record

Record only non-sensitive evidence: commit SHA, deployment run URL, HTTP status, table/policy names, product/order fixture IDs, and pass/fail results. Never record passwords, access tokens, refresh tokens, full delivery addresses, or private customer details.
