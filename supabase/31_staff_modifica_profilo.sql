-- ============================================================
--  CAMON · LO STAFF PUO' MODIFICARE I DATI DI UN CLIENTE
--
--  Le regole su 'profiles' lasciano lo staff LEGGERE tutti i
--  profili ("profili: staff legge tutti"), ma non c'e' alcuna
--  regola che lasci AGGIORNARLI. Serviva per la scheda cliente
--  dell'area titolare, quando si nota un dato sbagliato (telefono,
--  nome) e si vuole poterlo correggere li'.
--
--  Non si apre una policy di update generica: is_staff e' un campo
--  troppo delicato per lasciarlo scrivibile da chiunque abbia
--  is_staff — un account compromesso potrebbe promuoversi altri
--  account a staff in cascata. La funzione elenca ESPLICITAMENTE i
--  campi che si possono cambiare da qui: anagrafica, non ruoli.
--
--  Da eseguire nel SQL Editor DOPO 07_staff_area.sql.
-- ============================================================

create or replace function public.admin_update_profile(
  p_user_id    uuid,
  p_first_name text,
  p_last_name  text,
  p_phone      text,
  p_age        smallint,
  p_languages  text,
  p_erasmus    boolean,
  p_bio        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Solo lo staff puo'' modificare un profilo.';
  end if;

  update public.profiles
     set first_name = p_first_name,
         last_name  = p_last_name,
         phone      = p_phone,
         age        = p_age,
         languages  = p_languages,
         erasmus    = p_erasmus,
         bio        = p_bio,
         updated_at = now()
   where id = p_user_id;

  if not found then
    raise exception 'Cliente non trovato.';
  end if;
end $$;

revoke all on function public.admin_update_profile(uuid, text, text, text, smallint, text, boolean, text) from public;
revoke all on function public.admin_update_profile(uuid, text, text, text, smallint, text, boolean, text) from anon;
grant execute on function public.admin_update_profile(uuid, text, text, text, smallint, text, boolean, text) to authenticated;
