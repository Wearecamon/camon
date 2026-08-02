-- ============================================================
--  CAMON · AREA TITOLARE
--  Aggiunge il ruolo staff, le tabelle che finora mancavano
--  (prenotazioni e richieste feste vivevano solo nel browser)
--  e la gestione di menu e giochi dall'app.
--
--  Da eseguire nel SQL Editor DOPO 01..06.
-- ============================================================

-- ------------------------------------------------------------
--  1) RUOLO STAFF
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists is_staff boolean not null default false;

-- Serve una funzione a parte: interrogare "profiles" da dentro una
-- policy di "profiles" andrebbe in ricorsione. SECURITY DEFINER
-- salta il controllo RLS e spezza il giro.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_staff from public.profiles where id = auth.uid()), false);
$$;

revoke all on function public.is_staff() from public;
grant execute on function public.is_staff() to authenticated;

-- ------------------------------------------------------------
--  2) PRENOTAZIONI TAVOLI
-- ------------------------------------------------------------
create table if not exists public.bookings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  booking_type  text not null check (booking_type in ('shared','private','room','invite')),
  booking_date  date,
  booking_time  text,
  people        integer,
  table_code    text,
  occasion      text,
  notes         text,
  status        text not null default 'attiva'
                check (status in ('attiva','annullata','completata')),
  created_at    timestamptz not null default now()
);
create index if not exists bookings_date_idx on public.bookings (booking_date desc);
create index if not exists bookings_user_idx on public.bookings (user_id);

-- ------------------------------------------------------------
--  3) RICHIESTE FESTA PRIVATA
--     Non sono prenotazioni confermate: il locale richiama.
-- ------------------------------------------------------------
create table if not exists public.event_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete set null,
  event_date   date not null,
  event_time   text,
  occasion     text,
  mood         text,
  guests       text,
  full_name    text not null,
  phone        text not null,
  email        text not null,
  notes        text,
  status       text not null default 'nuova'
               check (status in ('nuova','contattato','confermata','annullata')),
  created_at   timestamptz not null default now()
);
create index if not exists event_requests_created_idx on public.event_requests (created_at desc);

-- ------------------------------------------------------------
--  4) GIOCHI ACCENDIBILI/SPEGNIBILI
--     La riga esiste solo per i giochi che il titolare vuole
--     poter nascondere; l'app parte dall'elenco che ha in casa.
-- ------------------------------------------------------------
create table if not exists public.games (
  key         text primary key,
  name        text not null,
  enabled     boolean not null default true,
  sort_order  integer not null default 0,
  updated_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
--  5) SICUREZZA
-- ------------------------------------------------------------
alter table public.bookings       enable row level security;
alter table public.event_requests enable row level security;
alter table public.games          enable row level security;

--  PROFILI: lo staff li vede tutti (serve per l'elenco clienti)
drop policy if exists "profili: staff legge tutti" on public.profiles;
create policy "profili: staff legge tutti" on public.profiles
  for select using (public.is_staff());

--  PRENOTAZIONI: l'utente le proprie, lo staff tutte
drop policy if exists "prenotazioni: leggo le mie"   on public.bookings;
drop policy if exists "prenotazioni: creo le mie"    on public.bookings;
drop policy if exists "prenotazioni: staff legge"    on public.bookings;
drop policy if exists "prenotazioni: staff aggiorna" on public.bookings;
create policy "prenotazioni: leggo le mie"   on public.bookings
  for select using (auth.uid() = user_id);
create policy "prenotazioni: creo le mie"    on public.bookings
  for insert with check (auth.uid() = user_id);
create policy "prenotazioni: staff legge"    on public.bookings
  for select using (public.is_staff());
create policy "prenotazioni: staff aggiorna" on public.bookings
  for update using (public.is_staff());

--  RICHIESTE FESTE: le manda anche chi non ha un account, quindi
--  l'inserimento e' aperto; a rileggerle e' solo lo staff.
drop policy if exists "feste: chiunque richiede" on public.event_requests;
drop policy if exists "feste: leggo le mie"      on public.event_requests;
drop policy if exists "feste: staff legge"       on public.event_requests;
drop policy if exists "feste: staff aggiorna"    on public.event_requests;
create policy "feste: chiunque richiede" on public.event_requests
  for insert with check (true);
create policy "feste: leggo le mie"      on public.event_requests
  for select using (auth.uid() is not null and auth.uid() = user_id);
create policy "feste: staff legge"       on public.event_requests
  for select using (public.is_staff());
create policy "feste: staff aggiorna"    on public.event_requests
  for update using (public.is_staff());

--  PRODOTTI: lettura per tutti (gia' definita), scrittura allo staff
drop policy if exists "prodotti: staff aggiorna" on public.products;
create policy "prodotti: staff aggiorna" on public.products
  for update using (public.is_staff());

--  GIOCHI: li legge chiunque, li cambia lo staff
drop policy if exists "giochi: leggibili da tutti" on public.games;
drop policy if exists "giochi: staff aggiorna"     on public.games;
drop policy if exists "giochi: staff inserisce"    on public.games;
create policy "giochi: leggibili da tutti" on public.games for select using (true);
create policy "giochi: staff aggiorna"     on public.games for update using (public.is_staff());
create policy "giochi: staff inserisce"    on public.games for insert with check (public.is_staff());

--  MOVIMENTI e PORTAFOGLI: allo staff servono per la dashboard saldi
drop policy if exists "wallet: staff legge" on public.wallets;
create policy "wallet: staff legge" on public.wallets
  for select using (public.is_staff());

drop policy if exists "tx: staff legge" on public.transactions;
create policy "tx: staff legge" on public.transactions
  for select using (public.is_staff());

drop policy if exists "ordini: staff legge" on public.orders;
create policy "ordini: staff legge" on public.orders
  for select using (public.is_staff());

drop policy if exists "righe: staff legge" on public.order_items;
create policy "righe: staff legge" on public.order_items
  for select using (public.is_staff());

-- ------------------------------------------------------------
--  6) NOMINA TE STESSO TITOLARE
--     Sostituisci l'indirizzo con quello del tuo account CAMON
--     e togli il commento prima di eseguire.
-- ------------------------------------------------------------
-- update public.profiles set is_staff = true
-- where id = (select id from auth.users where email = 'tua@email.it');
