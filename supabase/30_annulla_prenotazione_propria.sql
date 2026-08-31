-- ============================================================
--  CAMON · IL CLIENTE PUO' ANNULLARE LA PROPRIA PRENOTAZIONE
--
--  Le regole su 'bookings' lasciano un cliente creare la propria
--  prenotazione e leggerla, ma non AGGIORNARLA — solo lo staff puo'
--  farlo ("prenotazioni: staff aggiorna"). Per questo "Annulla
--  prenotazione" nel flusso manuale (tavolo condiviso/privato/stanza,
--  diverso dagli inviti) non faceva niente sul database: resettava
--  solo lo stato del telefono.
--
--  Non si allarga la policy di update a tutti i campi — un cliente
--  potrebbe cambiarsi da solo il tavolo assegnato. Si passa da una
--  funzione che lascia fare solo la cosa giusta: annullare la
--  PROPRIA prenotazione, niente altro.
--
--  Da eseguire nel SQL Editor DOPO 07_staff_area.sql.
-- ============================================================

create or replace function public.booking_cancel_mine(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  update public.bookings
     set status = 'annullata'
   where id = p_booking_id
     and user_id = v_me
     and status = 'attiva';

  if not found then
    raise exception 'Prenotazione non trovata o gia'' annullata.';
  end if;
end $$;

revoke all on function public.booking_cancel_mine(uuid) from public;
revoke all on function public.booking_cancel_mine(uuid) from anon;
grant execute on function public.booking_cancel_mine(uuid) to authenticated;
