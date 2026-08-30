-- ============================================================
--  CAMON · SOLO PER TEST — permette di invitare se stessi
--
--  Serve per provare il meccanico degli inviti da un solo account,
--  senza doverne avere due. NON lasciarlo attivo quando l'app va in
--  mano ai clienti veri: un invito "segreto" a se stessi non ha
--  senso e confonderebbe solo chi lo trovasse per sbaglio.
--
--  Per tornare alla normalita' dopo i test, esegui
--  26_fine_test_autoinvito.sql — rimette esattamente le regole di
--  24_inviti_segreti.sql, senza doverle riscrivere a mano.
--
--  Da eseguire nel SQL Editor DOPO 24_inviti_segreti.sql.
-- ============================================================

-- Il vincolo sulla tabella blocca sender_id = recipient_id a monte,
-- prima ancora che le funzioni vengano interpellate: va tolto anche
-- lui, non basta aggirarlo nelle funzioni.
alter table public.invites drop constraint if exists invites_non_a_se_stessi;

-- invite_send: uguale a 24, ma senza il controllo "non puoi invitare te stesso"
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

-- search_people: uguale a 23, ma senza escludere se stessi dai risultati
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
  if v_me is null then
    return;
  end if;
  if length(v_q) < 2 then
    return;
  end if;

  return query
    select p.id,
           btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as full_name,
           p.photo_url
      from public.profiles p
     where btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) <> ''
       and (
             coalesce(p.first_name, '') ilike '%' || v_q || '%'
          or coalesce(p.last_name,  '') ilike '%' || v_q || '%'
          or btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) ilike '%' || v_q || '%'
       )
     order by full_name
     limit 8;
end $$;
