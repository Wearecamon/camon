-- ============================================================
--  CAMON · Funzioni NFC lato server
--  Tutte le operazioni su carta fisica passano da qui.
--
--  FUNZIONI:
--    nfc_register   → collega una carta a un utente (staff)
--    nfc_lookup     → trova utente + saldo da UID carta
--    nfc_spend      → scala saldo tramite UID carta (spillatore)
--    nfc_recharge   → ricarica tramite UID carta (cassa)
-- ============================================================

-- ------------------------------------------------------------
--  REGISTRA CARTA
--  Chiamata dallo staff quando associa una tessera a un utente.
--  Se la carta esiste già la riassegna.
-- ------------------------------------------------------------
create or replace function public.nfc_register(
  p_uid     text,       -- UID esadecimale letto dal lettore
  p_user_id uuid        -- utente a cui associarla
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_uid is null or trim(p_uid) = '' then
    raise exception 'UID non valido';
  end if;

  insert into public.nfc_cards (uid, user_id, active)
  values (upper(trim(p_uid)), p_user_id, true)
  on conflict (uid)
  do update set user_id = excluded.user_id,
                active   = true;
end $$;

-- ------------------------------------------------------------
--  LOOKUP CARTA
--  Ritorna: user_id, nome, saldo in centesimi.
--  Usata dal totem per identificare chi avvicina la carta.
-- ------------------------------------------------------------
create or replace function public.nfc_lookup(
  p_uid text
)
returns table (
  user_id      uuid,
  first_name   text,
  last_name    text,
  balance_cents integer
)
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_active  boolean;
begin
  select nc.user_id, nc.active
    into v_user_id, v_active
    from public.nfc_cards nc
   where nc.uid = upper(trim(p_uid));

  if v_user_id is null then
    raise exception 'CARD_NOT_FOUND';
  end if;
  if not v_active then
    raise exception 'CARD_INACTIVE';
  end if;

  return query
    select p.id, p.first_name, p.last_name, w.balance_cents
      from public.profiles p
      join public.wallets  w on w.user_id = p.id
     where p.id = v_user_id;
end $$;

-- ------------------------------------------------------------
--  SPESA TRAMITE CARTA (spillatore / totem)
--  Identifica l'utente dall'UID e scala il saldo.
--  Ritorna il nuovo saldo in centesimi.
-- ------------------------------------------------------------
create or replace function public.nfc_spend(
  p_uid          text,
  p_amount_cents integer,
  p_description  text default 'Spillata'
)
returns integer   -- nuovo saldo in centesimi
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_active  boolean;
  v_bal     integer;
  v_new     integer;
begin
  -- trova carta
  select nc.user_id, nc.active
    into v_user_id, v_active
    from public.nfc_cards nc
   where nc.uid = upper(trim(p_uid));

  if v_user_id is null then
    raise exception 'CARD_NOT_FOUND';
  end if;
  if not v_active then
    raise exception 'CARD_INACTIVE';
  end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Importo non valido';
  end if;

  -- legge saldo con lock per evitare doppie spese
  select balance_cents into v_bal
    from public.wallets
   where user_id = v_user_id
   for update;

  if v_bal is null then
    raise exception 'Portafoglio inesistente';
  end if;
  if v_bal < p_amount_cents then
    raise exception 'SALDO_INSUFFICIENTE';
  end if;

  -- scala
  update public.wallets
     set balance_cents = balance_cents - p_amount_cents,
         updated_at    = now()
   where user_id = v_user_id
   returning balance_cents into v_new;

  -- registra movimento
  insert into public.transactions (user_id, type, amount_cents, description)
  values (v_user_id, 'spend', p_amount_cents, p_description);

  return v_new;
end $$;

-- ------------------------------------------------------------
--  RICARICA TRAMITE CARTA (cassa / staff)
--  Identifica l'utente dall'UID e aggiunge credito.
--  Ritorna il nuovo saldo in centesimi.
-- ------------------------------------------------------------
create or replace function public.nfc_recharge(
  p_uid          text,
  p_amount_cents integer,
  p_description  text default 'Ricarica al banco'
)
returns integer   -- nuovo saldo in centesimi
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_active  boolean;
  v_new     integer;
begin
  -- trova carta
  select nc.user_id, nc.active
    into v_user_id, v_active
    from public.nfc_cards nc
   where nc.uid = upper(trim(p_uid));

  if v_user_id is null then
    raise exception 'CARD_NOT_FOUND';
  end if;
  if not v_active then
    raise exception 'CARD_INACTIVE';
  end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Importo non valido';
  end if;

  -- aggiunge saldo
  update public.wallets
     set balance_cents = balance_cents + p_amount_cents,
         updated_at    = now()
   where user_id = v_user_id
   returning balance_cents into v_new;

  -- registra movimento
  insert into public.transactions (user_id, type, amount_cents, description)
  values (v_user_id, 'recharge', p_amount_cents, p_description);

  return v_new;
end $$;

-- ------------------------------------------------------------
--  RLS: le funzioni sono security definer → girano come
--  postgres, non come utente. Nessuna policy aggiuntiva
--  necessaria — ma verifica che nfc_cards sia protetta:
-- ------------------------------------------------------------
alter table public.nfc_cards enable row level security;

-- staff e service_role possono fare tutto
drop policy if exists "service_role full access on nfc_cards" on public.nfc_cards;
create policy "service_role full access on nfc_cards"
  on public.nfc_cards for all
  to service_role using (true);

-- utenti autenticati vedono solo le proprie carte
drop policy if exists "user sees own cards" on public.nfc_cards;
create policy "user sees own cards"
  on public.nfc_cards for select
  to authenticated using (user_id = auth.uid());
