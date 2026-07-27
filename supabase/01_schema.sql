-- ============================================================
--  CAMON · Schema database (Supabase / PostgreSQL)
--  Versione completa: utenti, portafoglio, movimenti,
--  carte NFC, prodotti, ordini, punteggi giochi.
--
--  COME USARLO:
--  Supabase → SQL Editor → New query → incolla tutto → Run.
--  È idempotente: puoi rilanciarlo senza rompere nulla.
-- ============================================================

-- Estensioni utili
create extension if not exists "pgcrypto";        -- gen_random_uuid()

-- ------------------------------------------------------------
--  ENUM (tipi chiusi)
-- ------------------------------------------------------------
do $$ begin
  create type tx_type   as enum ('recharge', 'spend', 'refund', 'bonus');
end $$;
do $$ begin
  create type order_status as enum ('pending', 'paid', 'served', 'cancelled');
end $$;
do $$ begin
  create type macro_type as enum ('drink', 'cibo');
end $$;

-- ============================================================
--  1) PROFILI  (estende auth.users)
--     auth.users è gestita da Supabase; qui i dati "app".
-- ============================================================
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  first_name   text,
  last_name    text,
  birthdate    date,
  gender       text,
  bio          text,
  photo_url    text,
  erasmus      boolean not null default false,
  languages    text,
  phone        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ============================================================
--  2) PORTAFOGLIO  (un saldo per utente)
--     Il saldo NON si scrive mai a mano: lo muovono le funzioni
--     wallet_recharge / wallet_spend (vedi 03_functions.sql).
-- ============================================================
create table if not exists public.wallets (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  balance_cents integer not null default 0 check (balance_cents >= 0),
  updated_at   timestamptz not null default now()
);

-- ============================================================
--  3) MOVIMENTI  (storico immutabile del portafoglio)
-- ============================================================
create table if not exists public.transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  type         tx_type not null,
  amount_cents integer not null check (amount_cents > 0),
  description  text,
  order_id     uuid,                       -- opzionale, collega alla spesa
  created_at   timestamptz not null default now()
);
create index if not exists idx_tx_user_date on public.transactions (user_id, created_at desc);

-- ============================================================
--  4) CARTE NFC  (tessere fisiche legate all'utente)
-- ============================================================
create table if not exists public.nfc_cards (
  id           uuid primary key default gen_random_uuid(),
  uid          text unique not null,       -- seriale della tessera
  user_id      uuid references auth.users(id) on delete set null,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_nfc_user on public.nfc_cards (user_id);

-- ============================================================
--  5) PRODOTTI  (menu: drink e cibo)  — leggibili da tutti
-- ============================================================
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  macro        macro_type not null,        -- drink | cibo
  category     text not null,              -- cocktail, birra, burger, ...
  price_cents  integer not null check (price_cents >= 0),
  description  text,
  emoji        text,
  available    boolean not null default true,
  sort         integer not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists idx_products_cat on public.products (macro, category);

-- ============================================================
--  6) ORDINI + RIGHE
-- ============================================================
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  total_cents  integer not null default 0 check (total_cents >= 0),
  status       order_status not null default 'pending',
  created_at   timestamptz not null default now()
);
create index if not exists idx_orders_user on public.orders (user_id, created_at desc);

create table if not exists public.order_items (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  product_id   uuid references public.products(id) on delete set null,
  name         text not null,              -- copia il nome al momento dell'ordine
  unit_cents   integer not null check (unit_cents >= 0),
  quantity     integer not null check (quantity > 0),
  created_at   timestamptz not null default now()
);
create index if not exists idx_items_order on public.order_items (order_id);

-- ============================================================
--  7) PUNTEGGI GIOCHI
-- ============================================================
create table if not exists public.game_scores (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  game         text not null,              -- 'shotquest', 'beerpong', ...
  score        integer not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists idx_scores_game on public.game_scores (game, score desc);

-- ============================================================
--  8) updated_at automatico
-- ============================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_profiles_touch on public.profiles;
create trigger trg_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ============================================================
--  9) Alla registrazione: crea profilo + portafoglio a 0
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  insert into public.wallets (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
