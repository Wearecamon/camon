-- ============================================================
--  CAMON · IL DESTINATARIO PUO' DISDIRE LA SUA PRENOTAZIONE
--
--  Finora "Annulla prenotazione" era nascosto per le prenotazioni
--  nate da un invito: il vecchio bottone non tocca il database,
--  sarebbe stato disonesto lasciarlo. Qui la versione vera —
--  cancella davvero la prenotazione, e avvisa chi ha invitato.
--
--  Stato nuovo, 'disdetto', distinto da 'annullato': quello e' gia'
--  usato per il caso opposto (il MITTENTE disdice un cambio data
--  proposto dal destinatario). Tenerli separati evita che lo stesso
--  stato debba raccontare due storie diverse a seconda di chi ha
--  agito — il banner del mittente per 'annullato' non ha senso per
--  questo caso, e viceversa.
--
--  Da eseguire nel SQL Editor DOPO 24_inviti_segreti.sql.
-- ============================================================

alter table public.invites drop constraint if exists invites_status_check;
alter table public.invites add constraint invites_status_check
  check (status in ('in_attesa', 'accettato', 'rifiutato', 'annullato', 'disdetto'));

create or replace function public.invite_recipient_cancel_booking(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_inv record;
begin
  select * into v_inv from public.invites where id = p_invite_id for update;
  if v_inv is null then
    raise exception 'Invito non trovato.';
  end if;
  if v_inv.recipient_id <> v_me then
    raise exception 'Non e'' la tua prenotazione.';
  end if;
  if v_inv.status <> 'accettato' then
    raise exception 'Questa prenotazione non e'' (piu'') attiva.';
  end if;

  if v_inv.booking_id is not null then
    update public.bookings set status = 'annullata' where id = v_inv.booking_id;
  end if;

  update public.invites
     set status = 'disdetto',
         seen_by_sender = false,   -- il mittente non lo sa ancora
         seen_by_recipient = true, -- lei l'ha appena fatto
         updated_at = now()
   where id = p_invite_id;
end $$;

revoke all on function public.invite_recipient_cancel_booking(uuid) from public;
revoke all on function public.invite_recipient_cancel_booking(uuid) from anon;
grant execute on function public.invite_recipient_cancel_booking(uuid) to authenticated;
