-- ============================================================
--  CAMON · FINE TEST — rimette le regole normali sull'autoinvito
--
--  Da eseguire quando hai finito di provare il meccanico degli
--  inviti da un solo account. Rimette esattamente quello che c'era
--  in 24_inviti_segreti.sql e 23_ricerca_persone.sql.
--
--  Prima di eseguirlo: se hai creato un invito verso te stesso per
--  provare, cancellalo (o accettalo/rifiutalo, cosi' non resta a
--  meta') — altrimenti il vincolo qui sotto non si puo' rimettere,
--  perche' quella riga lo violerebbe. Dalla tabella invites nel
--  Table Editor di Supabase, o con:
--    delete from public.invites where sender_id = recipient_id;
-- ============================================================

alter table public.invites
  add constraint invites_non_a_se_stessi check (sender_id <> recipient_id);

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
