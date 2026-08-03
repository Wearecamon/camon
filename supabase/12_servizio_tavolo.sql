-- ============================================================
--  CAMON · SERVIZIO AL TAVOLO
--  Chi ordina sceglie se ritirare al banco o farsi servire al
--  tavolo; il servizio costa 1 euro. Il supplemento lo calcola
--  il server insieme al resto: se arrivasse dal telefono si
--  potrebbe farsi servire senza pagarlo.
--
--  Da eseguire nel SQL Editor DOPO 10.
-- ============================================================

alter table public.orders
  add column if not exists service_mode text not null default 'banco',
  add column if not exists service_fee_cents integer not null default 0;

alter table public.orders
  drop constraint if exists orders_service_mode_check;
alter table public.orders
  add constraint orders_service_mode_check
  check (service_mode in ('banco', 'tavolo'));

-- ------------------------------------------------------------
--  CREA E PAGA L'ORDINE (sostituisce la versione della 09)
-- ------------------------------------------------------------
create or replace function public.order_create(
  p_items        jsonb,
  p_table_code   text default null,
  p_note         text default null,
  p_service_mode text default 'banco'
)
returns table (order_id uuid, total_cents integer, new_balance integer)
language plpgsql security definer set search_path = public as $$
declare
  v_user     uuid := auth.uid();
  v_subtot   integer := 0;
  v_servizio integer := 0;
  v_total    integer := 0;
  v_bal      integer;
  v_new      integer;
  v_order    uuid;
  v_righe    integer;
  v_modo     text := coalesce(nullif(trim(p_service_mode), ''), 'banco');
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Ordine vuoto';
  end if;
  if v_modo not in ('banco', 'tavolo') then
    raise exception 'Modalita'' di servizio non valida';
  end if;

  create temp table _righe on commit drop as
  select
    (i->>'product_id')::uuid as product_id,
    greatest(1, least(50, coalesce((i->>'quantity')::int, 1))) as quantity
  from jsonb_array_elements(p_items) as i;

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

  select coalesce(sum(quantity * price_cents), 0) into v_subtot from _calcolo;

  -- il supplemento lo decide il server, non chi ordina
  v_servizio := case when v_modo = 'tavolo' then 100 else 0 end;
  v_total := v_subtot + v_servizio;

  select balance_cents into v_bal
    from public.wallets where user_id = v_user for update;
  if v_bal is null then
    raise exception 'Portafoglio inesistente';
  end if;
  if v_bal < v_total then
    raise exception 'Saldo insufficiente';
  end if;

  insert into public.orders (user_id, total_cents, status, table_code, note,
                             service_mode, service_fee_cents)
  values (v_user, v_total, 'paid', p_table_code, p_note, v_modo, v_servizio)
  returning id into v_order;

  insert into public.order_items (order_id, product_id, name, unit_cents, quantity)
  select v_order, product_id, name, price_cents, quantity from _calcolo;

  update public.wallets
     set balance_cents = balance_cents - v_total, updated_at = now()
   where user_id = v_user
   returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description, order_id)
  values (v_user, 'spend', v_total,
          case when v_modo = 'tavolo' then 'Ordine al tavolo' else 'Ordine da ritirare' end,
          v_order);

  return query select v_order, v_total, v_new;
end $$;

revoke all on function public.order_create(jsonb, text, text, text) from public;
grant execute on function public.order_create(jsonb, text, text, text) to authenticated;

-- La vecchia firma a 3 parametri non serve piu': si toglie per
-- evitare che resti in giro una versione senza supplemento.
drop function if exists public.order_create(jsonb, text, text);
