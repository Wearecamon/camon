-- ============================================================
--  CAMON · ORDINAZIONI DAL TAVOLO
--  L'ordine si crea solo da qui. I prezzi li rilegge il server
--  dalla tabella prodotti: se arrivassero dal telefono, chiunque
--  potrebbe ordinare una bottiglia al prezzo che preferisce.
--  Creazione righe e addebito stanno nella stessa transazione,
--  quindi non esistono ordini pagati a meta'.
--
--  Da eseguire nel SQL Editor DOPO 08.
-- ============================================================

alter table public.orders
  add column if not exists table_code text,
  add column if not exists note text;

-- Lo staff deve poter segnare l'ordine come servito
drop policy if exists "ordini: staff aggiorna" on public.orders;
create policy "ordini: staff aggiorna" on public.orders
  for update using (public.is_staff());

-- ------------------------------------------------------------
--  CREA E PAGA L'ORDINE
--  p_items: [{"product_id":"…","quantity":2}, …]
-- ------------------------------------------------------------
create or replace function public.order_create(
  p_items      jsonb,
  p_table_code text default null,
  p_note       text default null
)
returns table (order_id uuid, total_cents integer, new_balance integer)
language plpgsql security definer set search_path = public as $$
declare
  v_user  uuid := auth.uid();
  v_total integer := 0;
  v_bal   integer;
  v_new   integer;
  v_order uuid;
  v_righe integer;
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Ordine vuoto';
  end if;

  -- Righe richieste, ripulite: quantita' sensate e prodotto esistente
  create temp table _righe on commit drop as
  select
    (i->>'product_id')::uuid as product_id,
    greatest(1, least(50, coalesce((i->>'quantity')::int, 1))) as quantity
  from jsonb_array_elements(p_items) as i;

  -- Il prezzo viene dal database, non da chi ordina
  create temp table _calcolo on commit drop as
  select r.product_id, r.quantity, p.name, p.price_cents
    from _righe r
    join public.products p on p.id = r.product_id
   where p.available;

  select count(*) into v_righe from _calcolo;
  if v_righe = 0 then
    raise exception 'Nessun prodotto disponibile nell''ordine';
  end if;
  if v_righe <> (select count(*) from _righe) then
    raise exception 'Un prodotto non e'' piu'' disponibile';
  end if;

  select coalesce(sum(quantity * price_cents), 0) into v_total from _calcolo;

  -- Blocca il portafoglio finche' la transazione non chiude
  select balance_cents into v_bal
    from public.wallets where user_id = v_user for update;
  if v_bal is null then
    raise exception 'Portafoglio inesistente';
  end if;
  if v_bal < v_total then
    raise exception 'Saldo insufficiente';
  end if;

  insert into public.orders (user_id, total_cents, status, table_code, note)
  values (v_user, v_total, 'paid', p_table_code, p_note)
  returning id into v_order;

  insert into public.order_items (order_id, product_id, name, unit_cents, quantity)
  select v_order, product_id, name, price_cents, quantity from _calcolo;

  update public.wallets
     set balance_cents = balance_cents - v_total, updated_at = now()
   where user_id = v_user
   returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description, order_id)
  values (v_user, 'spend', v_total, 'Ordine al tavolo', v_order);

  return query select v_order, v_total, v_new;
end $$;

revoke all on function public.order_create(jsonb, text, text) from public;
grant execute on function public.order_create(jsonb, text, text) to authenticated;
