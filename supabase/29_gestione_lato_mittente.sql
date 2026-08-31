-- ============================================================
--  CAMON · CHI HA INVITATO PUO' GESTIRE LA PRENOTAZIONE
--
--  Finora il mittente poteva disdire solo se il destinatario aveva
--  cambiato data (era l'unico caso in cui "quella sera non posso"
--  aveva senso, nella progettazione iniziale). Ora puo' disdire
--  qualunque invito accettato, come qualunque altra prenotazione.
--
--  E serve una via per LEGGERE i dati della prenotazione: la riga su
--  'bookings' appartiene al destinatario (e' lei/lui che l'ha creata
--  accettando), quindi la regola "leggo le mie" non lascia passare il
--  mittente. Non si allarga quella regola — resterebbe un problema di
--  privacy per tutte le altre prenotazioni — si passa da una funzione
--  che lascia leggere solo i campi utili (tavolo, data), e solo a chi
--  ha davvero mandato quell'invito.
--
--  Da eseguire nel SQL Editor DOPO 24_inviti_segreti.sql.
-- ============================================================

create or replace function public.invite_sender_cancel(p_invite_id uuid)
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
  if v_inv.sender_id <> v_me then
    raise exception 'Non e'' il tuo invito.';
  end if;
  if v_inv.status <> 'accettato' then
    raise exception 'Questa prenotazione non e'' (piu'') attiva.';
  end if;

  if v_inv.booking_id is not null then
    update public.bookings set status = 'annullata' where id = v_inv.booking_id;
  end if;

  update public.invites
     set status = 'annullato',
         seen_by_recipient = false,
         seen_by_sender = true,
         updated_at = now()
   where id = p_invite_id;
end $$;

revoke all on function public.invite_sender_cancel(uuid) from public;
revoke all on function public.invite_sender_cancel(uuid) from anon;
grant execute on function public.invite_sender_cancel(uuid) to authenticated;

-- ------------------------------------------------------------
--  Dati della prenotazione per il mittente: solo tavolo, data,
--  persone. Niente che non gli serva, niente che riguardi altri.
-- ------------------------------------------------------------
create or replace function public.invite_booking_for_sender(p_invite_id uuid)
returns table (
  table_code   text,
  booking_date date,
  people       integer,
  status       text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_inv record;
begin
  select * into v_inv from public.invites where id = p_invite_id;
  if v_inv is null or v_inv.sender_id <> v_me then
    return;
  end if;
  if v_inv.booking_id is null then
    return;
  end if;

  return query
    select b.table_code, b.booking_date, b.people, b.status
      from public.bookings b
     where b.id = v_inv.booking_id;
end $$;

revoke all on function public.invite_booking_for_sender(uuid) from public;
revoke all on function public.invite_booking_for_sender(uuid) from anon;
grant execute on function public.invite_booking_for_sender(uuid) to authenticated;
