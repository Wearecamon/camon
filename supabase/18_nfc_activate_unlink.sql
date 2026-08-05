-- ============================================================
--  NFC: attiva / rimuovi braccialetto dal proprio account
--  (mancavano — prima l'attivazione e la rimozione erano solo
--  locali sul dispositivo, mai sincronizzate su Supabase)
-- ============================================================

-- ------------------------------------------------------------
--  ATTIVA CARTA
--  Rende attiva la carta p_uid per l'utente p_user_id e
--  disattiva tutte le altre carte dello stesso utente.
-- ------------------------------------------------------------
create or replace function public.nfc_set_active(
  p_uid     text,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.nfc_cards
     set active = (uid = upper(trim(p_uid)))
   where user_id = p_user_id;
end $$;

-- ------------------------------------------------------------
--  RIMUOVI CARTA
--  Scollega la carta p_uid dall'utente p_user_id (solo se è sua).
-- ------------------------------------------------------------
create or replace function public.nfc_unlink(
  p_uid     text,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.nfc_cards
   where uid = upper(trim(p_uid))
     and user_id = p_user_id;
end $$;
