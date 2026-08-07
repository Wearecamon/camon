-- ============================================================
--  Abilita Supabase Realtime su wallets e transactions, così
--  l'app può ascoltare in diretta i cambi di saldo (es. quando
--  il totem fa una ricarica/spesa tramite braccialetto NFC) senza
--  dover uscire e rientrare dalla sezione Carta.
--  Sicuro da rieseguire più volte.
-- ============================================================
alter publication supabase_realtime add table public.wallets;
alter publication supabase_realtime add table public.transactions;
