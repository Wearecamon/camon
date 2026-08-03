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
