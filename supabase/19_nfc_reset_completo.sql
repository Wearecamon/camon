-- ============================================================
--  CAMON · NFC — RESET COMPLETO
--  Esegui questo file UNA VOLTA, tutto intero, nell'SQL Editor
--  di Supabase. È sicuro rieseguirlo più volte (idempotente).
--
--  Copre: tabella nfc_cards, RLS, e tutte le funzioni usate
--  dall'app (collega / attiva / rimuovi / lookup / spesa / ricarica),
--  con i permessi di esecuzione espliciti per gli utenti loggati
--  (che sono la causa più probabile se "Collega" non salvava nulla
--  senza mostrare errori).
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABELLA
-- ------------------------------------------------------------
create table if not exists public.nfc_cards (
  id           uuid primary key default gen_random_uuid(),
  uid          text unique not null,
  user_id      uuid references auth.users(id) on delete set null,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_nfc_user on public.nfc_cards (user_id);

-- ------------------------------------------------------------
-- 2) RLS — l'utente vede solo le proprie carte, tutte le scritture
--    passano dalle funzioni qui sotto (security definer)
-- ------------------------------------------------------------
alter table public.nfc_cards enable row level security;

drop policy if exists "service_role full access on nfc_cards" on public.nfc_cards;
create policy "service_role full access on nfc_cards"
  on public.nfc_cards for all
  to service_role using (true);

drop policy if exists "user sees own cards" on public.nfc_cards;
create policy "user sees own cards"
  on public.nfc_cards for select
  to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------
-- 3) FUNZIONI
-- ------------------------------------------------------------

-- COLLEGA carta all'utente che la registra (self-service dall'app)
create or replace function public.nfc_register(
  p_uid     text,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_uid is null or trim(p_uid) = '' then
    raise exception 'UID non valido';
  end if;
  if p_user_id is null or p_user_id <> auth.uid() then
    raise exception 'Non autorizzato';
  end if;

  insert into public.nfc_cards (uid, user_id, active)
  values (upper(trim(p_uid)), p_user_id, true)
  on conflict (uid)
  do update set user_id = excluded.user_id,
                active   = true;
end $$;

-- ATTIVA una carta (e disattiva le altre dello stesso utente)
create or replace function public.nfc_set_active(
  p_uid     text,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user_id is null or p_user_id <> auth.uid() then
    raise exception 'Non autorizzato';
  end if;
  update public.nfc_cards
     set active = (uid = upper(trim(p_uid)))
   where user_id = p_user_id;
end $$;

-- RIMUOVI carta dall'account
create or replace function public.nfc_unlink(
  p_uid     text,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user_id is null or p_user_id <> auth.uid() then
    raise exception 'Non autorizzato';
  end if;
  delete from public.nfc_cards
   where uid = upper(trim(p_uid))
     and user_id = p_user_id;
end $$;

-- LOOKUP (usata dal totem/NFC per identificare l'utente dalla tessera)
create or replace function public.nfc_lookup(
  p_uid text
)
returns table (
  user_id       uuid,
  first_name    text,
  last_name     text,
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

  if v_user_id is null then raise exception 'CARD_NOT_FOUND'; end if;
  if not v_active then raise exception 'CARD_INACTIVE'; end if;

  return query
    select p.id, p.first_name, p.last_name, w.balance_cents
      from public.profiles p
      join public.wallets  w on w.user_id = p.id
     where p.id = v_user_id;
end $$;

-- SPESA tramite carta (spillatore/totem, ruolo staff/service)
create or replace function public.nfc_spend(
  p_uid          text,
  p_amount_cents integer,
  p_description  text default 'Spillata'
)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid; v_active boolean; v_bal integer; v_new integer;
begin
  select nc.user_id, nc.active into v_user_id, v_active
    from public.nfc_cards nc where nc.uid = upper(trim(p_uid));
  if v_user_id is null then raise exception 'CARD_NOT_FOUND'; end if;
  if not v_active then raise exception 'CARD_INACTIVE'; end if;
  if p_amount_cents is null or p_amount_cents <= 0 then raise exception 'Importo non valido'; end if;

  select balance_cents into v_bal from public.wallets where user_id = v_user_id for update;
  if v_bal is null then raise exception 'Portafoglio inesistente'; end if;
  if v_bal < p_amount_cents then raise exception 'SALDO_INSUFFICIENTE'; end if;

  update public.wallets set balance_cents = balance_cents - p_amount_cents, updated_at = now()
   where user_id = v_user_id returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description)
  values (v_user_id, 'spend', p_amount_cents, p_description);

  return v_new;
end $$;

-- RICARICA tramite carta (cassa/staff)
create or replace function public.nfc_recharge(
  p_uid          text,
  p_amount_cents integer,
  p_description  text default 'Ricarica al banco'
)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid; v_active boolean; v_new integer;
begin
  select nc.user_id, nc.active into v_user_id, v_active
    from public.nfc_cards nc where nc.uid = upper(trim(p_uid));
  if v_user_id is null then raise exception 'CARD_NOT_FOUND'; end if;
  if not v_active then raise exception 'CARD_INACTIVE'; end if;
  if p_amount_cents is null or p_amount_cents <= 0 then raise exception 'Importo non valido'; end if;

  update public.wallets set balance_cents = balance_cents + p_amount_cents, updated_at = now()
   where user_id = v_user_id returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description)
  values (v_user_id, 'recharge', p_amount_cents, p_description);

  return v_new;
end $$;

-- ------------------------------------------------------------
-- 4) PERMESSI DI ESECUZIONE — questa è la parte che mancava.
--    Senza questi GRANT, l'app (ruolo "authenticated") non può
--    chiamare le funzioni: la RPC fallisce con "permission denied
--    for function ..." (o silenziosamente, a seconda del client).
-- ------------------------------------------------------------
grant execute on function public.nfc_register(text, uuid)        to authenticated;
grant execute on function public.nfc_set_active(text, uuid)      to authenticated;
grant execute on function public.nfc_unlink(text, uuid)          to authenticated;
grant execute on function public.nfc_lookup(text)                to authenticated, service_role;
grant execute on function public.nfc_spend(text, integer, text)  to authenticated, service_role;
grant execute on function public.nfc_recharge(text, integer, text) to authenticated, service_role;
