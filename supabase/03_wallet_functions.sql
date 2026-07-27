-- ============================================================
--  CAMON · Logica portafoglio lato server
--  Il saldo si muove SOLO da qui: così il client non può
--  falsificarlo e ricarica/spesa restano atomiche.
--
--  Importi sempre in CENTESIMI (interi) per evitare errori
--  di arrotondamento. €3,50 -> 350.
-- ============================================================

-- ------------------------------------------------------------
--  RICARICA
--  Da chiamare DOPO l'incasso reale (es. webhook Stripe).
--  In test la puoi invocare a mano.
-- ------------------------------------------------------------
create or replace function public.wallet_recharge(
  p_amount_cents integer,
  p_description  text default 'Ricarica'
)
returns integer                       -- nuovo saldo in centesimi
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_new  integer;
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Importo non valido';
  end if;

  update public.wallets
     set balance_cents = balance_cents + p_amount_cents,
         updated_at = now()
   where user_id = v_user
   returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description)
  values (v_user, 'recharge', p_amount_cents, p_description);

  return v_new;
end $$;

-- ------------------------------------------------------------
--  SPESA
--  Scala il saldo se sufficiente, altrimenti errore.
--  Il lock (for update) evita doppie spese in contemporanea.
-- ------------------------------------------------------------
create or replace function public.wallet_spend(
  p_amount_cents integer,
  p_description  text default 'Consumazione',
  p_order_id     uuid default null
)
returns integer                       -- nuovo saldo in centesimi
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_bal  integer;
  v_new  integer;
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Importo non valido';
  end if;

  select balance_cents into v_bal
    from public.wallets
   where user_id = v_user
   for update;                        -- blocca la riga fino a fine transazione

  if v_bal is null then
    raise exception 'Portafoglio inesistente';
  end if;
  if v_bal < p_amount_cents then
    raise exception 'Saldo insufficiente';
  end if;

  update public.wallets
     set balance_cents = balance_cents - p_amount_cents,
         updated_at = now()
   where user_id = v_user
   returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description, order_id)
  values (v_user, 'spend', p_amount_cents, p_description, p_order_id);

  return v_new;
end $$;
