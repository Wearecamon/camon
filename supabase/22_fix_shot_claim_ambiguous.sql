-- ============================================================
--  FIX: shot_claim() falliva con "column reference \"code\" is
--  ambiguous". La funzione dichiara RETURNS TABLE (code text, ...),
--  che crea un parametro di output chiamato "code" — dentro al corpo
--  della funzione questo confligge col nome della colonna "code"
--  della tabella shot_codes usata nel WHERE del controllo duplicati.
--  Qui sotto la stessa funzione, con la tabella alias "sc" e le
--  colonne qualificate esplicitamente per togliere l'ambiguità.
-- ============================================================
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
    select 1 from public.shot_codes sc
     where sc.user_id = v_user and sc.created_at >= v_reset
  ) then
    raise exception 'Bonus gia'' richiesto per questa serata';
  end if;

  -- quattro cifre a caso, ripescate se gia' in giro fra i codici vivi
  loop
    v_code := 'CMN-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (
      select 1 from public.shot_codes sc
       where sc.code = v_code and sc.redeemed_at is null and sc.expires_at > now()
    );
  end loop;

  insert into public.shot_codes (user_id, code, expires_at)
  values (v_user, v_code, v_exp);

  return query select v_code, v_exp;
end $$;

revoke all on function public.shot_claim() from public;
grant execute on function public.shot_claim() to authenticated;
