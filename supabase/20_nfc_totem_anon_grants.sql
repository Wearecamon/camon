-- ============================================================
--  Il totem (totem.html) non ha un login utente: chiama le RPC
--  con la chiave pubblica (ruolo "anon"). Senza questi permessi,
--  nfc_lookup/nfc_spend/nfc_recharge falliscono con "permission
--  denied" quando chiamate dal totem.
--
--  Sicurezza: queste funzioni restano protette perché richiedono
--  di conoscere l'UID fisico della carta (letto dal lettore NFC
--  al banco) — non basta conoscere l'email/id di un utente per
--  usarle, a differenza di nfc_register/nfc_set_active/nfc_unlink
--  che restano riservate a "authenticated" (servono per l'app,
--  dove l'utente collega le SUE carte al proprio account).
-- ============================================================
grant execute on function public.nfc_lookup(text)                  to anon;
grant execute on function public.nfc_spend(text, integer, text)    to anon;
grant execute on function public.nfc_recharge(text, integer, text) to anon;
