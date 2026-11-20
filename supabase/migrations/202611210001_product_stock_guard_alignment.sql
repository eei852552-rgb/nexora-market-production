-- Align the QA product guard with the production hardening definition.
-- The COD order-item SECURITY DEFINER trigger decrements stock while auth.uid()
-- is the buyer. Seller approval remains enforced by product INSERT/UPDATE RLS
-- policies; it must not block this internal stock update.
create or replace function public.nexora_product_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    if tg_op = 'INSERT' then
      if new.seller_id is distinct from auth.uid() then
        raise exception 'seller_id must match the authenticated user';
      end if;
      new.status := 'draft';
    elsif tg_op = 'UPDATE' then
      if new.seller_id is distinct from old.seller_id then
        raise exception 'seller_id cannot change';
      end if;
      if new.status is distinct from old.status then
        new.status := old.status;
      end if;
    end if;
  end if;
  return new;
end;
$$;
