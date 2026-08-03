-- ============================================================
--  CAMON · Collega l'avviso email alle richieste feste
--
--  ESEGUI SOLO DOPO aver rilasciato la funzione:
--    supabase functions deploy avviso-festa --no-verify-jwt
--  (istruzioni complete in functions/avviso-festa/index.ts)
--
--  Se salti questo file non si rompe nulla: le richieste
--  continuano ad arrivare in dashboard, semplicemente non parte
--  la mail.
-- ============================================================

-- pg_net manda la chiamata senza bloccare chi sta salvando la richiesta
create extension if not exists pg_net with schema extensions;

-- Sostituisci con l'indirizzo della tua funzione, che trovi nel
-- pannello Supabase alla voce Edge Functions.
create or replace function public.notifica_festa()
returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_url text := 'https://vbwttxfkyvbrmykwodqi.supabase.co/functions/v1/avviso-festa';
begin
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
exception when others then
  -- L'avviso non deve mai far fallire la richiesta del cliente:
  -- meglio una mail persa che una prenotazione persa.
  return new;
end $$;

drop trigger if exists on_event_request_created on public.event_requests;
create trigger on_event_request_created
  after insert on public.event_requests
  for each row execute function public.notifica_festa();
