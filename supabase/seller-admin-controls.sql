-- Applied to Supabase project nbhfdiiehukdtusxksni as add_seller_admin_controls.
-- Seller approval is required before product CRUD or advertising drafts.

create table if not exists public.seller_applications (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, business_name text not null check (char_length(trim(business_name)) between 2 and 150), phone text not null check (char_length(trim(phone)) between 6 and 40), category text not null default 'Other', note text not null default '' check (char_length(note) <= 1000), status text not null default 'pending' check (status in ('pending','approved','rejected')), admin_note text not null default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (user_id));
create table if not exists public.advertisements (id uuid primary key default gen_random_uuid(), seller_id uuid not null references auth.users(id) on delete cascade, title text not null check (char_length(trim(title)) between 2 and 150), description text not null default '' check (char_length(description) <= 1000), image_url text, target_url text, budget_mmk numeric not null default 0 check (budget_mmk >= 0), status text not null default 'draft' check (status in ('draft','pending','approved','paused','rejected')), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.commissions (id uuid primary key default gen_random_uuid(), seller_id uuid not null references auth.users(id) on delete cascade, order_id uuid references public.orders(id) on delete set null, amount_mmk numeric not null check (amount_mmk >= 0), rate numeric not null default 0 check (rate >= 0 and rate <= 100), status text not null default 'pending' check (status in ('pending','settled','void')), created_at timestamptz not null default now());
alter table public.seller_applications enable row level security;
alter table public.advertisements enable row level security;
alter table public.commissions enable row level security;
create or replace function private.is_approved_seller() returns boolean language sql stable security definer set search_path=public as $$ select exists (select 1 from public.seller_applications where user_id = auth.uid() and status = 'approved'); $$;
create policy seller_applications_owner_or_admin_read on public.seller_applications for select to authenticated using (user_id = auth.uid() or private.is_admin());
create policy seller_applications_owner_insert on public.seller_applications for insert to authenticated with check (user_id = auth.uid() and status = 'pending');
create policy seller_applications_owner_or_admin_update on public.seller_applications for update to authenticated using ((user_id = auth.uid() and status in ('pending','rejected')) or private.is_admin()) with check (private.is_admin() or (user_id = auth.uid() and status = 'pending'));
create policy seller_applications_owner_or_admin_delete on public.seller_applications for delete to authenticated using ((user_id = auth.uid() and status = 'pending') or private.is_admin());
create policy ads_public_approved_read on public.advertisements for select to anon, authenticated using (status = 'approved');
create policy ads_owner_or_admin_read on public.advertisements for select to authenticated using (seller_id = auth.uid() or private.is_admin());
create policy ads_owner_or_admin_insert on public.advertisements for insert to authenticated with check (private.is_admin() or (seller_id = auth.uid() and private.is_approved_seller() and status = 'draft'));
create policy ads_owner_or_admin_update on public.advertisements for update to authenticated using (seller_id = auth.uid() or private.is_admin()) with check (seller_id = auth.uid() or private.is_admin());
create policy ads_owner_or_admin_delete on public.advertisements for delete to authenticated using (seller_id = auth.uid() or private.is_admin());
create policy commissions_seller_or_admin_read on public.commissions for select to authenticated using (seller_id = auth.uid() or private.is_admin());
create policy commissions_admin_write on public.commissions for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy products_admin_all on public.products for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy products_approved_seller_insert on public.products for insert to authenticated with check (seller_id = auth.uid() and private.is_approved_seller());
create policy products_approved_seller_update on public.products for update to authenticated using (seller_id = auth.uid() and private.is_approved_seller()) with check (seller_id = auth.uid() and private.is_approved_seller());
create policy products_approved_seller_delete on public.products for delete to authenticated using (seller_id = auth.uid() and private.is_approved_seller());
create policy products_approved_seller_read_own on public.products for select to authenticated using (seller_id = auth.uid() and private.is_approved_seller());
