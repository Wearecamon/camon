-- ============================================================
--  CAMON · RICERCA PERSONE (per l'invito segreto)
--
--  Il problema: la regola sui profili e' "leggo il mio"
--  (auth.uid() = id). Giusta cosi' — nessuno deve poter sfogliare
--  i dati degli altri — ma significa che una select dal telefono
--  torna solo se stessi. Per questo la ricerca dell'invito usava
--  una lista di nomi finti scritta dentro l'app.
--
--  La soluzione NON e' aprire la tabella in lettura a tutti:
--  li' dentro ci sono telefono, data di nascita, bio. Si passa da
--  una funzione SECURITY DEFINER che restituisce solo il minimo
--  che serve a riconoscere una persona in un elenco di ricerca:
--  nome, cognome, foto. Niente contatti, niente eta'.
--
--  Da eseguire nel SQL Editor DOPO 07.
-- ============================================================

create or replace function public.search_people(q text)
returns table (
  id         uuid,
  full_name  text,
  photo_url  text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_q    text := btrim(coalesce(q, ''));
begin
  -- Solo chi ha fatto l'accesso.
  if v_me is null then
    return;
  end if;

  -- Almeno due lettere: senza questo limite una stringa vuota
  -- restituirebbe l'anagrafica intera, che e' esattamente cio' che
  -- la regola sui profili serve a impedire.
  if length(v_q) < 2 then
    return;
  end if;

  return query
    select p.id,
           btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as full_name,
           p.photo_url
      from public.profiles p
     where p.id <> v_me
       and btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) <> ''
       and (
             coalesce(p.first_name, '') ilike '%' || v_q || '%'
          or coalesce(p.last_name,  '') ilike '%' || v_q || '%'
          or btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) ilike '%' || v_q || '%'
       )
     order by full_name
     limit 8;
end $$;

-- La funzione salta le regole di riga (security definer): va data
-- solo a chi ha l'accesso fatto, mai al ruolo anonimo.
revoke all on function public.search_people(text) from public;
revoke all on function public.search_people(text) from anon;
grant execute on function public.search_people(text) to authenticated;
