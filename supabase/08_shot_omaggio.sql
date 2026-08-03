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
