-- ============================================================
--  CAMON · Sicurezza (Row Level Security)
--  Regola d'oro: ognuno vede e modifica SOLO i propri dati.
--  I prodotti (menu) sono invece leggibili da tutti.
--
--  Incolla dopo 01_schema.sql nel SQL Editor e premi Run.
-- ============================================================

-- Attiva RLS su ogni tabella (senza policy = nessuno accede)
alter table public.profiles      enable row level security;
alter table public.wallets       enable row level security;
alter table public.transactions  enable row level security;
alter table public.nfc_cards     enable row level security;
alter table public.products      enable row level security;
alter table public.orders        enable row level security;
alter table public.order_items   enable row level security;
alter table public.game_scores   enable row level security;

-- ------------------------------------------------------------
--  PROFILI: ognuno il proprio
-- ------------------------------------------------------------
drop policy if exists "profili: leggo il mio"      on public.profiles;
drop policy if exists "profili: aggiorno il mio"   on public.profiles;
create policy "profili: leggo il mio"    on public.profiles for select using (auth.uid() = id);
create policy "profili: aggiorno il mio" on public.profiles for update using (auth.uid() = id);

-- ------------------------------------------------------------
--  PORTAFOGLIO: sola lettura del proprio saldo.
--  Le modifiche passano SOLO dalle funzioni server (SECURITY
--  DEFINER), non da insert/update diretti del client.
-- ------------------------------------------------------------
drop policy if exists "wallet: leggo il mio" on public.wallets;
create policy "wallet: leggo il mio" on public.wallets for select using (auth.uid() = user_id);

-- ------------------------------------------------------------
--  MOVIMENTI: sola lettura dei propri
-- ------------------------------------------------------------
drop policy if exists "tx: leggo i miei" on public.transactions;
create policy "tx: leggo i miei" on public.transactions for select using (auth.uid() = user_id);

-- ------------------------------------------------------------
--  CARTE NFC: l'utente vede le proprie
-- ------------------------------------------------------------
drop policy if exists "nfc: leggo le mie" on public.nfc_cards;
create policy "nfc: leggo le mie" on public.nfc_cards for select using (auth.uid() = user_id);

-- ------------------------------------------------------------
--  PRODOTTI: chiunque (anche non loggato) può leggere il menu.
--  La scrittura resta al personale (service_role), che bypassa RLS.
-- ------------------------------------------------------------
drop policy if exists "prodotti: leggibili da tutti" on public.products;
create policy "prodotti: leggibili da tutti" on public.products for select using (true);

-- ------------------------------------------------------------
--  ORDINI + RIGHE: l'utente crea e legge i propri ordini
-- ------------------------------------------------------------
drop policy if exists "ordini: leggo i miei"  on public.orders;
drop policy if exists "ordini: creo i miei"   on public.orders;
create policy "ordini: leggo i miei" on public.orders for select using (auth.uid() = user_id);
create policy "ordini: creo i miei"  on public.orders for insert with check (auth.uid() = user_id);

drop policy if exists "righe: leggo le mie" on public.order_items;
drop policy if exists "righe: creo le mie"  on public.order_items;
create policy "righe: leggo le mie" on public.order_items for select
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));
create policy "righe: creo le mie" on public.order_items for insert
  with check (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

-- ------------------------------------------------------------
--  PUNTEGGI GIOCHI: leggo i miei, li scrivo io.
--  (La classifica pubblica, se la vorrai, si fa con una VIEW
--   dedicata più avanti — così non esponi i user_id.)
-- ------------------------------------------------------------
drop policy if exists "punteggi: leggo i miei" on public.game_scores;
drop policy if exists "punteggi: creo i miei"  on public.game_scores;
create policy "punteggi: leggo i miei" on public.game_scores for select using (auth.uid() = user_id);
create policy "punteggi: creo i miei"  on public.game_scores for insert with check (auth.uid() = user_id);
