-- ============================================================
--  AGGIUNTA COLONNA "age" AI PROFILI
--  Il modulo del profilo chiede l'eta' in anni, non la data di
--  nascita: senza questa colonna il valore inserito si perdeva.
--  Il vincolo rispecchia i limiti del campo nell'app (18-99).
--  Da eseguire una sola volta nel SQL Editor di Supabase.
-- ============================================================

alter table public.profiles
  add column if not exists age smallint;

alter table public.profiles
  drop constraint if exists profiles_age_check;

alter table public.profiles
  add constraint profiles_age_check
  check (age is null or (age >= 18 and age <= 99));
