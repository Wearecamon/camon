-- ============================================================
--  CAMON · CORREZIONE — chi riceve l'invito non scopre mai chi e'
--
--  Prima: accettare rivelava l'identita' del mittente (era il testo
--  gia' scritto nel modulo dell'invito: "ti sveliamo chi sei solo se
--  accetta"). Corretto: NON deve rivelarla mai, nemmeno dopo
--  l'accettazione. Chi riceve arriva al tavolo condiviso, la persona
--  che l'ha invitata e' seduta li' con lei, ma resta un mistero — non
--  una rivelazione fatta dall'app.
--
--  Aggiorna solo invites_mine(): non tocca ne' invite_send ne'
--  search_people, quindi non disturba l'eventuale test autoinvito
--  (25_TEST_autoinvito.sql) gia' attivo.
--
--  Da eseguire nel SQL Editor DOPO 24_inviti_segreti.sql.
-- ============================================================

create or replace function public.invites_mine()
returns table (
  id                 uuid,
  direzione          text,
  altra_persona_id   uuid,
  altra_persona_nome text,
  altra_persona_foto text,
  proposed_date      date,
  reschedule_date    date,
  status             text,
  booking_id         uuid,
  non_letto          boolean,
  created_at         timestamptz,
  updated_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return;
  end if;

  return query
    -- Mandati: qui l'identita' dell'altra persona non e' mai stata un
    -- segreto — sei tu che l'hai scelta per invitarla.
    select
      i.id,
      'mandato'::text,
      i.recipient_id,
      btrim(coalesce(rp.first_name,'') || ' ' || coalesce(rp.last_name,'')),
      rp.photo_url,
      i.proposed_date, i.reschedule_date, i.status, i.booking_id,
      not i.seen_by_sender,
      i.created_at, i.updated_at
    from public.invites i
    join public.profiles rp on rp.id = i.recipient_id
    where i.sender_id = v_me
  union all
    -- Ricevuti: mai il nome, la foto o l'id di chi ha mandato
    -- l'invito — in nessuno stato, accettato compreso.
    select
      i.id,
      'ricevuto'::text,
      null::uuid,
      null::text,
      null::text,
      i.proposed_date, i.reschedule_date, i.status, i.booking_id,
      not i.seen_by_recipient,
      i.created_at, i.updated_at
    from public.invites i
    where i.recipient_id = v_me
  order by created_at desc;
end $$;

revoke all on function public.invites_mine() from public;
revoke all on function public.invites_mine() from anon;
grant execute on function public.invites_mine() to authenticated;
