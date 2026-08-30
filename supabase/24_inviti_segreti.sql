-- ============================================================
--  CAMON · INVITI SEGRETI
--
--  Finora l'invito non scriveva da nessuna parte: premere "Invia
--  invito segreto" mostrava solo un messaggio finto e resettava il
--  bottone. Questa tabella e le funzioni sotto rendono il meccanismo
--  vero: chi manda, chi riceve, con che data, e cosa succede quando
--  si accetta, si rifiuta o si cambia la data.
--
--  Il flusso della data, deciso esplicitamente: se il destinatario
--  propone un'altra sera, la prenotazione si conferma SUBITO su
--  quella — non aspetta una riconferma del mittente. Il mittente
--  viene solo avvisato, e se quella sera non puo' disdice lui (a
--  quel punto e' lei ad essere avvisata della disdetta).
--
--  Anonimato, stessa regola gia' scritta nel testo dell'app: "Resti
--  anonimo: gli sveliamo chi sei solo se accetta." Nessuna funzione
--  qui sotto lascia leggere sender_id a chi lo ha ricevuto finche'
--  lo stato non e' 'accettato'.
--
--  Da eseguire nel SQL Editor DOPO 07 e 23_ricerca_persone.sql.
-- ============================================================

create table if not exists public.invites (
  id                uuid primary key default gen_random_uuid(),
  sender_id         uuid not null references auth.users(id) on delete cascade,
  recipient_id      uuid not null references auth.users(id) on delete cascade,
  proposed_date     date not null,  -- la data che il mittente ha proposto all'inizio
  -- Valorizzata SOLO se il destinatario ha scelto un'altra sera invece
  -- di quella proposta. Da quel momento e' reschedule_date la data
  -- buona (la prenotazione e' gia' fatta su quella).
  reschedule_date   date,
  status            text not null default 'in_attesa'
                    check (status in (
                      'in_attesa',  -- mandato, il destinatario non ha ancora deciso
                      'accettato',  -- prenotazione creata (sulla data proposta o su quella cambiata), identita' rivelata
                      'rifiutato',  -- il destinatario ha detto no
                      'annullato'   -- il mittente ha disdetto dopo un cambio data
                    )),
  booking_id        uuid references public.bookings(id) on delete set null,
  -- L'ultimo cambiamento che l'altra parte non ha ancora visto: serve
  -- al banner per sapere se mostrare "hai un invito" o "e' successo
  -- qualcosa da guardare".
  seen_by_sender     boolean not null default true,  -- falso quando il destinatario agisce
  seen_by_recipient  boolean not null default false, -- falso quando c'e' un invito nuovo, o il mittente disdice un cambio data
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint invites_non_a_se_stessi check (sender_id <> recipient_id)
);
create index if not exists invites_recipient_idx on public.invites (recipient_id, status);
create index if not exists invites_sender_idx    on public.invites (sender_id, status);

-- ------------------------------------------------------------
--  SICUREZZA
--  Ognuno legge solo gli inviti che ha mandato o ricevuto — ma la
--  select diretta sulla tabella non basta a nascondere sender_id
--  finche' non e' accettato: quello lo fa la funzione invites_mine
--  qui sotto, che e' la via pensata per leggere. La riga resta
--  comunque protetta anche per chi provasse a leggerla a mano.
-- ------------------------------------------------------------
alter table public.invites enable row level security;

drop policy if exists "inviti: leggo i miei" on public.invites;
create policy "inviti: leggo i miei" on public.invites
  for select using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "inviti: staff legge tutti" on public.invites;
create policy "inviti: staff legge tutti" on public.invites
  for select using (public.is_staff());

-- Nessuna policy di insert/update dirette: si passa solo dalle
-- funzioni SECURITY DEFINER qui sotto, che controllano stato e
-- proprietario prima di scrivere.

-- ------------------------------------------------------------
--  INVIA
--  Un solo invito in_attesa per coppia mittente-destinatario alla
--  volta: rimandarne un secondo prima che il primo sia stato deciso
--  non ha senso e complicherebbe la coda che il destinatario vede.
-- ------------------------------------------------------------
create or replace function public.invite_send(p_recipient_id uuid, p_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'Devi accedere per mandare un invito.';
  end if;
  if p_recipient_id = v_me then
    raise exception 'Non puoi invitare te stesso.';
  end if;
  if p_date is null or p_date < current_date then
    raise exception 'Scegli una data da oggi in poi.';
  end if;
  if exists (
    select 1 from public.invites
     where sender_id = v_me and recipient_id = p_recipient_id and status = 'in_attesa'
  ) then
    raise exception 'gia_in_attesa';
  end if;

  insert into public.invites (sender_id, recipient_id, proposed_date)
  values (v_me, p_recipient_id, p_date)
  returning id into v_id;

  return v_id;
end $$;

revoke all on function public.invite_send(uuid, date) from public;
revoke all on function public.invite_send(uuid, date) from anon;
grant execute on function public.invite_send(uuid, date) to authenticated;

-- ------------------------------------------------------------
--  I MIEI INVITI (mandati + ricevuti)
--  L'unica via di lettura pensata per l'app. Rivela sender_id al
--  destinatario SOLO se status = 'accettato' — e' qui che si applica
--  la regola dell'anonimato, non nella policy di riga.
-- ------------------------------------------------------------
create or replace function public.invites_mine()
returns table (
  id                 uuid,
  direzione          text,   -- 'mandato' | 'ricevuto'
  altra_persona_id   uuid,   -- null se sono il destinatario e non e' ancora accettato
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
    -- Chi riceve non scopre mai chi ha mandato l'invito, nemmeno dopo
    -- averlo accettato: e' il punto del meccanismo. Arriva al tavolo
    -- condiviso e la persona che l'ha invitata e' una di quelle
    -- sedute li', ma resta un mistero — non una rivelazione in app.
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

-- ------------------------------------------------------------
--  Segna come vista (per il banner/pallino)
-- ------------------------------------------------------------
create or replace function public.invite_mark_seen(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  update public.invites
     set seen_by_sender    = case when sender_id    = v_me then true else seen_by_sender end,
         seen_by_recipient = case when recipient_id = v_me then true else seen_by_recipient end
   where id = p_invite_id
     and (sender_id = v_me or recipient_id = v_me);
end $$;

revoke all on function public.invite_mark_seen(uuid) from public;
revoke all on function public.invite_mark_seen(uuid) from anon;
grant execute on function public.invite_mark_seen(uuid) to authenticated;

-- ------------------------------------------------------------
--  ACCETTA (sulla data che il mittente ha proposto)
--  Crea la prenotazione — tavolo condiviso, 2 persone — e rivela
--  l'identita' spostando lo stato su 'accettato': e' invites_mine()
--  sopra che, vedendo questo stato, inizia a restituire sender_id
--  invece di null.
-- ------------------------------------------------------------
create or replace function public.invite_accept(p_invite_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_inv record;
  v_booking_id uuid;
begin
  select * into v_inv from public.invites where id = p_invite_id for update;
  if v_inv is null then
    raise exception 'Invito non trovato.';
  end if;
  if v_inv.recipient_id <> v_me then
    raise exception 'Non e'' il tuo invito.';
  end if;
  if v_inv.status <> 'in_attesa' then
    raise exception 'Questo invito non e'' piu'' decidibile.';
  end if;

  insert into public.bookings (user_id, booking_type, booking_date, people, status)
  values (v_me, 'shared', v_inv.proposed_date, 2, 'attiva')
  returning id into v_booking_id;

  update public.invites
     set status = 'accettato',
         booking_id = v_booking_id,
         seen_by_sender = false,   -- il mittente non sa ancora che ha accettato
         seen_by_recipient = true,
         updated_at = now()
   where id = p_invite_id;

  return v_booking_id;
end $$;

revoke all on function public.invite_accept(uuid) from public;
revoke all on function public.invite_accept(uuid) from anon;
grant execute on function public.invite_accept(uuid) to authenticated;

-- ------------------------------------------------------------
--  RIFIUTA
-- ------------------------------------------------------------
create or replace function public.invite_decline(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  update public.invites
     set status = 'rifiutato',
         seen_by_sender = false,
         seen_by_recipient = true,
         updated_at = now()
   where id = p_invite_id
     and recipient_id = v_me
     and status = 'in_attesa';

  if not found then
    raise exception 'Invito non trovato o gia'' deciso.';
  end if;
end $$;

revoke all on function public.invite_decline(uuid) from public;
revoke all on function public.invite_decline(uuid) from anon;
grant execute on function public.invite_decline(uuid) to authenticated;

-- ------------------------------------------------------------
--  CAMBIA DATA (il destinatario propone un'altra sera)
--  Come deciso: non e' una proposta che aspetta — la prenotazione si
--  fa SUBITO sulla nuova data, sullo stesso giro di invite_accept ma
--  con reschedule_date al posto di proposed_date. Il mittente viene
--  solo avvisato (seen_by_sender=false) e puo' disdire dopo, se
--  quella sera non gli va bene, con invite_sender_cancel qui sotto.
-- ------------------------------------------------------------
create or replace function public.invite_reschedule(p_invite_id uuid, p_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_inv record;
  v_booking_id uuid;
begin
  if p_date is null or p_date < current_date then
    raise exception 'Scegli una data da oggi in poi.';
  end if;

  select * into v_inv from public.invites where id = p_invite_id for update;
  if v_inv is null then
    raise exception 'Invito non trovato.';
  end if;
  if v_inv.recipient_id <> v_me then
    raise exception 'Non e'' il tuo invito.';
  end if;
  if v_inv.status <> 'in_attesa' then
    raise exception 'Questo invito non e'' piu'' decidibile.';
  end if;

  insert into public.bookings (user_id, booking_type, booking_date, people, status)
  values (v_me, 'shared', p_date, 2, 'attiva')
  returning id into v_booking_id;

  update public.invites
     set status = 'accettato',
         reschedule_date = p_date,
         booking_id = v_booking_id,
         seen_by_sender = false,
         seen_by_recipient = true,
         updated_at = now()
   where id = p_invite_id;

  return v_booking_id;
end $$;

revoke all on function public.invite_reschedule(uuid, date) from public;
revoke all on function public.invite_reschedule(uuid, date) from anon;
grant execute on function public.invite_reschedule(uuid, date) to authenticated;

-- ------------------------------------------------------------
--  IL MITTENTE DISDICE
--  Solo per il caso in cui il destinatario ha cambiato data (quella
--  sera per lui non va): annulla la prenotazione gia' fatta e chiude
--  l'invito. Il destinatario lo scopre alla prossima apertura —
--  seen_by_recipient torna falso apposta.
-- ------------------------------------------------------------
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
  if v_inv.status <> 'accettato' or v_inv.reschedule_date is null then
    raise exception 'Si puo'' disdire solo un invito con data cambiata dal destinatario.';
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
