-- ============================================================
--  Da eseguire PRIMA di 17_nfc_functions.sql se la tabella
--  nfc_cards non esiste ancora (es. se 01_schema.sql si è
--  fermato prima per via del tipo tx_type già esistente).
--  Sicuro da rieseguire più volte.
-- ============================================================

create table if not exists public.nfc_cards (
  id           uuid primary key default gen_random_uuid(),
  uid          text unique not null,       -- seriale della tessera
  user_id      uuid references auth.users(id) on delete set null,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_nfc_user on public.nfc_cards (user_id);
