-- ============================================================
--  CAMON · AGGIORNAMENTO COMPLETO DEL DATABASE
--
--  Questo file mette insieme le migrazioni dalla 05 alla 10.
--  Si incolla TUTTO in una volta nel SQL Editor di Supabase
--  e si preme Run. Si puo' rieseguire senza danni.
--
--  DOPO averlo eseguito, esegui anche la riga in fondo per
--  nominarti titolare (trovi le istruzioni li').
-- ============================================================


-- ############################################################
-- #  DA: 05_add_age.sql
-- ############################################################

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

-- ############################################################
-- #  DA: 06_avatars_storage.sql
-- ############################################################

-- ============================================================
--  FOTO PROFILO SU STORAGE
--  Prima le foto finivano in base64 dentro profiles.photo_url:
--  righe pesantissime e nessuna anteprima nel pannello. Ora sono
--  file veri in un bucket privato; nella colonna resta solo il
--  percorso, e l'app genera un link temporaneo per mostrarle.
--  Da eseguire una sola volta nel SQL Editor di Supabase.
-- ============================================================

-- Bucket privato: nessun accesso anonimo, si entra solo col token
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do update set public = false;

-- Ogni file sta in una cartella intitolata all'utente: "<uid>/avatar.jpg".
-- Le regole qui sotto confrontano quella cartella con chi sta scrivendo,
-- cosi' nessuno puo' toccare la foto di un altro.

drop policy if exists "avatar_insert_own" on storage.objects;
create policy "avatar_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatar_update_own" on storage.objects;
create policy "avatar_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatar_delete_own" on storage.objects;
create policy "avatar_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- In lettura serve piu' larghezza: ai tavoli sociali si vedono le foto
-- degli altri avventori. Resta comunque riservato a chi ha un account.
drop policy if exists "avatar_read_authenticated" on storage.objects;
create policy "avatar_read_authenticated" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

-- ############################################################
-- #  DA: 07_staff_area.sql
-- ############################################################

-- ============================================================
--  CAMON · AREA TITOLARE
--  Aggiunge il ruolo staff, le tabelle che finora mancavano
--  (prenotazioni e richieste feste vivevano solo nel browser)
--  e la gestione di menu e giochi dall'app.
--
--  Da eseguire nel SQL Editor DOPO 01..06.
-- ============================================================

-- ------------------------------------------------------------
--  1) RUOLO STAFF
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists is_staff boolean not null default false;

-- Serve una funzione a parte: interrogare "profiles" da dentro una
-- policy di "profiles" andrebbe in ricorsione. SECURITY DEFINER
-- salta il controllo RLS e spezza il giro.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_staff from public.profiles where id = auth.uid()), false);
$$;

revoke all on function public.is_staff() from public;
grant execute on function public.is_staff() to authenticated;

-- ------------------------------------------------------------
--  2) PRENOTAZIONI TAVOLI
-- ------------------------------------------------------------
create table if not exists public.bookings (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  booking_type  text not null check (booking_type in ('shared','private','room','invite')),
  booking_date  date,
  booking_time  text,
  people        integer,
  table_code    text,
  occasion      text,
  notes         text,
  status        text not null default 'attiva'
                check (status in ('attiva','annullata','completata')),
  created_at    timestamptz not null default now()
);
create index if not exists bookings_date_idx on public.bookings (booking_date desc);
create index if not exists bookings_user_idx on public.bookings (user_id);

-- ------------------------------------------------------------
--  3) RICHIESTE FESTA PRIVATA
--     Non sono prenotazioni confermate: il locale richiama.
-- ------------------------------------------------------------
create table if not exists public.event_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete set null,
  event_date   date not null,
  event_time   text,
  occasion     text,
  mood         text,
  guests       text,
  full_name    text not null,
  phone        text not null,
  email        text not null,
  notes        text,
  status       text not null default 'nuova'
               check (status in ('nuova','contattato','confermata','annullata')),
  created_at   timestamptz not null default now()
);
create index if not exists event_requests_created_idx on public.event_requests (created_at desc);

-- ------------------------------------------------------------
--  4) GIOCHI ACCENDIBILI/SPEGNIBILI
--     La riga esiste solo per i giochi che il titolare vuole
--     poter nascondere; l'app parte dall'elenco che ha in casa.
-- ------------------------------------------------------------
create table if not exists public.games (
  key         text primary key,
  name        text not null,
  enabled     boolean not null default true,
  sort_order  integer not null default 0,
  updated_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
--  5) SICUREZZA
-- ------------------------------------------------------------
alter table public.bookings       enable row level security;
alter table public.event_requests enable row level security;
alter table public.games          enable row level security;

--  PROFILI: lo staff li vede tutti (serve per l'elenco clienti)
drop policy if exists "profili: staff legge tutti" on public.profiles;
create policy "profili: staff legge tutti" on public.profiles
  for select using (public.is_staff());

--  PRENOTAZIONI: l'utente le proprie, lo staff tutte
drop policy if exists "prenotazioni: leggo le mie"   on public.bookings;
drop policy if exists "prenotazioni: creo le mie"    on public.bookings;
drop policy if exists "prenotazioni: staff legge"    on public.bookings;
drop policy if exists "prenotazioni: staff aggiorna" on public.bookings;
create policy "prenotazioni: leggo le mie"   on public.bookings
  for select using (auth.uid() = user_id);
create policy "prenotazioni: creo le mie"    on public.bookings
  for insert with check (auth.uid() = user_id);
create policy "prenotazioni: staff legge"    on public.bookings
  for select using (public.is_staff());
create policy "prenotazioni: staff aggiorna" on public.bookings
  for update using (public.is_staff());

--  RICHIESTE FESTE: le manda anche chi non ha un account, quindi
--  l'inserimento e' aperto; a rileggerle e' solo lo staff.
drop policy if exists "feste: chiunque richiede" on public.event_requests;
drop policy if exists "feste: leggo le mie"      on public.event_requests;
drop policy if exists "feste: staff legge"       on public.event_requests;
drop policy if exists "feste: staff aggiorna"    on public.event_requests;
create policy "feste: chiunque richiede" on public.event_requests
  for insert with check (true);
create policy "feste: leggo le mie"      on public.event_requests
  for select using (auth.uid() is not null and auth.uid() = user_id);
create policy "feste: staff legge"       on public.event_requests
  for select using (public.is_staff());
create policy "feste: staff aggiorna"    on public.event_requests
  for update using (public.is_staff());

--  PRODOTTI: lettura per tutti (gia' definita), scrittura allo staff
drop policy if exists "prodotti: staff aggiorna" on public.products;
create policy "prodotti: staff aggiorna" on public.products
  for update using (public.is_staff());

--  GIOCHI: li legge chiunque, li cambia lo staff
drop policy if exists "giochi: leggibili da tutti" on public.games;
drop policy if exists "giochi: staff aggiorna"     on public.games;
drop policy if exists "giochi: staff inserisce"    on public.games;
create policy "giochi: leggibili da tutti" on public.games for select using (true);
create policy "giochi: staff aggiorna"     on public.games for update using (public.is_staff());
create policy "giochi: staff inserisce"    on public.games for insert with check (public.is_staff());

--  MOVIMENTI e PORTAFOGLI: allo staff servono per la dashboard saldi
drop policy if exists "wallet: staff legge" on public.wallets;
create policy "wallet: staff legge" on public.wallets
  for select using (public.is_staff());

drop policy if exists "tx: staff legge" on public.transactions;
create policy "tx: staff legge" on public.transactions
  for select using (public.is_staff());

drop policy if exists "ordini: staff legge" on public.orders;
create policy "ordini: staff legge" on public.orders
  for select using (public.is_staff());

drop policy if exists "righe: staff legge" on public.order_items;
create policy "righe: staff legge" on public.order_items
  for select using (public.is_staff());

-- ------------------------------------------------------------
--  6) NOMINA TE STESSO TITOLARE
--     Sostituisci l'indirizzo con quello del tuo account CAMON
--     e togli il commento prima di eseguire.
-- ------------------------------------------------------------
-- update public.profiles set is_staff = true
-- where id = (select id from auth.users where email = 'tua@email.it');

-- ############################################################
-- #  DA: 08_shot_omaggio.sql
-- ############################################################

-- ============================================================
--  CAMON · SHOT OMAGGIO VERIFICABILE
--  Prima il codice nasceva nel telefono, era prevedibile (stessa
--  data + stesso profilo = stesso codice) e il limite di uno a
--  serata si aggirava svuotando i dati del browser. Soprattutto:
--  nessuno registrava il ritiro, quindi lo stesso codice poteva
--  essere mostrato piu' volte.
--
--  Da eseguire nel SQL Editor DOPO 07.
-- ============================================================

create table if not exists public.shot_codes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  code        text not null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null
);
create index if not exists shot_codes_code_idx on public.shot_codes (code);
create index if not exists shot_codes_user_idx on public.shot_codes (user_id, created_at desc);

alter table public.shot_codes enable row level security;

drop policy if exists "shot: leggo i miei"  on public.shot_codes;
drop policy if exists "shot: staff legge"   on public.shot_codes;
create policy "shot: leggo i miei" on public.shot_codes
  for select using (auth.uid() = user_id);
create policy "shot: staff legge"  on public.shot_codes
  for select using (public.is_staff());
-- nessuna policy di insert/update: si passa solo dalle funzioni qui sotto

-- ------------------------------------------------------------
--  Ultimo azzeramento: le 8:00 di Torino piu' recenti
-- ------------------------------------------------------------
create or replace function public.shot_reset_point()
returns timestamptz
language plpgsql stable as $$
declare
  v_ora   timestamp := now() at time zone 'Europe/Rome';
  v_reset timestamp;
begin
  v_reset := date_trunc('day', v_ora) + interval '8 hours';
  if v_ora < v_reset then
    v_reset := v_reset - interval '1 day';
  end if;
  return v_reset at time zone 'Europe/Rome';
end $$;

-- ------------------------------------------------------------
--  RICHIESTA DEL CODICE (cliente)
--  Uno per serata, deciso dal server: il telefono non puo'
--  piu' fabbricarselo ne' azzerare il limite.
-- ------------------------------------------------------------
create or replace function public.shot_claim()
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_user  uuid := auth.uid();
  v_reset timestamptz := public.shot_reset_point();
  v_code  text;
  v_exp   timestamptz := now() + interval '15 minutes';
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;

  if exists (
    select 1 from public.shot_codes
     where user_id = v_user and created_at >= v_reset
  ) then
    raise exception 'Bonus gia'' richiesto per questa serata';
  end if;

  -- quattro cifre a caso, ripescate se gia' in giro fra i codici vivi
  loop
    v_code := 'CMN-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (
      select 1 from public.shot_codes
       where code = v_code and redeemed_at is null and expires_at > now()
    );
  end loop;

  insert into public.shot_codes (user_id, code, expires_at)
  values (v_user, v_code, v_exp);

  return query select v_code, v_exp;
end $$;

revoke all on function public.shot_claim() from public;
grant execute on function public.shot_claim() to authenticated;

-- ------------------------------------------------------------
--  VERIFICA (staff): dice cosa fare senza consumare il codice
-- ------------------------------------------------------------
create or replace function public.shot_verify(p_code text)
returns table (
  stato       text,
  cliente     text,
  creato      timestamptz,
  scade       timestamptz,
  ritirato_il timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_row public.shot_codes%rowtype;
begin
  if not public.is_staff() then
    raise exception 'Riservato allo staff';
  end if;

  select * into v_row from public.shot_codes
   where code = upper(trim(p_code))
   order by created_at desc limit 1;

  if not found then
    return query select 'inesistente'::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz;
    return;
  end if;

  return query
  select
    case
      when v_row.redeemed_at is not null then 'gia_usato'
      when v_row.expires_at < now()      then 'scaduto'
      else 'valido'
    end::text,
    coalesce(nullif(trim(coalesce(p.first_name,'') || ' ' || coalesce(p.last_name,'')), ''), 'Cliente')::text,
    v_row.created_at, v_row.expires_at, v_row.redeemed_at
  from public.profiles p where p.id = v_row.user_id;
end $$;

revoke all on function public.shot_verify(text) from public;
grant execute on function public.shot_verify(text) to authenticated;

-- ------------------------------------------------------------
--  RITIRO (staff): segna il codice come consegnato.
--  La condizione nell'update fa da guardia: due addetti che
--  premono insieme non riescono a consegnarlo due volte.
-- ------------------------------------------------------------
create or replace function public.shot_redeem(p_code text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not public.is_staff() then
    raise exception 'Riservato allo staff';
  end if;

  update public.shot_codes
     set redeemed_at = now(), redeemed_by = auth.uid()
   where code = upper(trim(p_code))
     and redeemed_at is null
     and expires_at > now()
   returning id into v_id;

  if v_id is null then
    raise exception 'Codice non valido, scaduto o gia'' consegnato';
  end if;
  return 'ok';
end $$;

revoke all on function public.shot_redeem(text) from public;
grant execute on function public.shot_redeem(text) to authenticated;

-- ############################################################
-- #  DA: 09_ordini.sql
-- ############################################################

-- ============================================================
--  CAMON · ORDINAZIONI DAL TAVOLO
--  L'ordine si crea solo da qui. I prezzi li rilegge il server
--  dalla tabella prodotti: se arrivassero dal telefono, chiunque
--  potrebbe ordinare una bottiglia al prezzo che preferisce.
--  Creazione righe e addebito stanno nella stessa transazione,
--  quindi non esistono ordini pagati a meta'.
--
--  Da eseguire nel SQL Editor DOPO 08.
-- ============================================================

alter table public.orders
  add column if not exists table_code text,
  add column if not exists note text;

-- Lo staff deve poter segnare l'ordine come servito
drop policy if exists "ordini: staff aggiorna" on public.orders;
create policy "ordini: staff aggiorna" on public.orders
  for update using (public.is_staff());

-- ------------------------------------------------------------
--  CREA E PAGA L'ORDINE
--  p_items: [{"product_id":"…","quantity":2}, …]
-- ------------------------------------------------------------
create or replace function public.order_create(
  p_items      jsonb,
  p_table_code text default null,
  p_note       text default null
)
returns table (order_id uuid, total_cents integer, new_balance integer)
language plpgsql security definer set search_path = public as $$
declare
  v_user  uuid := auth.uid();
  v_total integer := 0;
  v_bal   integer;
  v_new   integer;
  v_order uuid;
  v_righe integer;
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Ordine vuoto';
  end if;

  -- Righe richieste, ripulite: quantita' sensate e prodotto esistente
  create temp table _righe on commit drop as
  select
    (i->>'product_id')::uuid as product_id,
    greatest(1, least(50, coalesce((i->>'quantity')::int, 1))) as quantity
  from jsonb_array_elements(p_items) as i;

  -- Il prezzo viene dal database, non da chi ordina
  create temp table _calcolo on commit drop as
  select r.product_id, r.quantity, p.name, p.price_cents
    from _righe r
    join public.products p on p.id = r.product_id
   where p.available;

  select count(*) into v_righe from _calcolo;
  if v_righe = 0 then
    raise exception 'Nessun prodotto disponibile nell''ordine';
  end if;
  if v_righe <> (select count(*) from _righe) then
    raise exception 'Un prodotto non e'' piu'' disponibile';
  end if;

  select coalesce(sum(quantity * price_cents), 0) into v_total from _calcolo;

  -- Blocca il portafoglio finche' la transazione non chiude
  select balance_cents into v_bal
    from public.wallets where user_id = v_user for update;
  if v_bal is null then
    raise exception 'Portafoglio inesistente';
  end if;
  if v_bal < v_total then
    raise exception 'Saldo insufficiente';
  end if;

  insert into public.orders (user_id, total_cents, status, table_code, note)
  values (v_user, v_total, 'paid', p_table_code, p_note)
  returning id into v_order;

  insert into public.order_items (order_id, product_id, name, unit_cents, quantity)
  select v_order, product_id, name, price_cents, quantity from _calcolo;

  update public.wallets
     set balance_cents = balance_cents - v_total, updated_at = now()
   where user_id = v_user
   returning balance_cents into v_new;

  insert into public.transactions (user_id, type, amount_cents, description, order_id)
  values (v_user, 'spend', v_total, 'Ordine al tavolo', v_order);

  return query select v_order, v_total, v_new;
end $$;

revoke all on function public.order_create(jsonb, text, text) from public;
grant execute on function public.order_create(jsonb, text, text) to authenticated;

-- ############################################################
-- #  DA: 10_privacy.sql
-- ############################################################

-- ============================================================
--  CAMON · PRIVACY
--  Traccia dei consensi e cancellazione dell'account da parte
--  dell'utente, come richiede il GDPR (diritto alla cancellazione).
--
--  Da eseguire nel SQL Editor DOPO 09.
-- ============================================================

-- ------------------------------------------------------------
--  1) QUANDO SONO STATI DATI I CONSENSI
--     Servono per dimostrare che l'utente ha accettato: senza
--     data e ora il consenso non e' documentabile.
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists consent_at      timestamptz,
  add column if not exists age_declared_at timestamptz;

-- Il trigger di registrazione li copia dai dati dell'iscrizione
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, consent_at, age_declared_at)
  values (
    new.id,
    (new.raw_user_meta_data ->> 'consent_at')::timestamptz,
    (new.raw_user_meta_data ->> 'age_declared_at')::timestamptz
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

-- ------------------------------------------------------------
--  2) CANCELLAZIONE DELL'ACCOUNT
--     Ordini e movimenti non si cancellano: sono documenti
--     contabili. Si staccano dalla persona (user_id a null) e
--     spariscono i dati che la identificano.
-- ------------------------------------------------------------
alter table public.transactions
  drop constraint if exists transactions_user_id_fkey;
alter table public.transactions
  add constraint transactions_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;
alter table public.transactions alter column user_id drop not null;

alter table public.orders
  drop constraint if exists orders_user_id_fkey;
alter table public.orders
  add constraint orders_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;
alter table public.orders alter column user_id drop not null;

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;

  -- prima i dati personali veri e propri
  delete from public.profiles  where id = v_user;
  delete from public.wallets   where user_id = v_user;
  delete from public.nfc_cards where user_id = v_user;
  delete from public.shot_codes where user_id = v_user;

  -- le richieste feste restano al locale ma perdono l'aggancio
  update public.event_requests set user_id = null where user_id = v_user;
  update public.bookings        set user_id = null where user_id = v_user;

  -- infine l'utenza: ordini e movimenti restano, orfani
  delete from auth.users where id = v_user;
end $$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ------------------------------------------------------------
--  3) COPIA DEI PROPRI DATI (diritto di accesso)
-- ------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Non autenticato';
  end if;

  return jsonb_build_object(
    'profilo',      (select to_jsonb(p) from public.profiles p where p.id = v_user),
    'portafoglio',  (select to_jsonb(w) from public.wallets w where w.user_id = v_user),
    'movimenti',    (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                       from public.transactions t where t.user_id = v_user),
    'ordini',       (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                       from public.orders o where o.user_id = v_user),
    'prenotazioni', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb)
                       from public.bookings b where b.user_id = v_user),
    'feste',        (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                       from public.event_requests e where e.user_id = v_user)
  );
end $$;

revoke all on function public.export_my_data() from public;
grant execute on function public.export_my_data() to authenticated;


-- ############################################################
-- #  ULTIMO PASSO: NOMINATI TITOLARE
-- #  Gia' pronto con l'indirizzo dell'account CAMON.
-- ############################################################

update public.profiles
   set is_staff = true
 where id = (select id from auth.users
              where lower(email) = 'fiandinomarco01@gmail.com');

-- Controllo: deve comparire una riga con is_staff = true
select u.email, p.is_staff
  from public.profiles p
  join auth.users u on u.id = p.id
 where lower(u.email) = 'fiandinomarco01@gmail.com';
