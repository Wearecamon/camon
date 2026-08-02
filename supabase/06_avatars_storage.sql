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
