-- ============================================================
--  CAMON · FASCIA DELLA PRENOTAZIONE
--  Chi prenota dice se si ferma a cena, a cena e dopo, oppure
--  solo dopocena.
--
--  Il solo dopocena e' riservato ai TAVOLI CONDIVISI. Sugli altri
--  terrebbe il tavolo bloccato lasciandolo vuoto nelle ore di
--  cena, che e' quando vale di piu': chi vuole venire piu' tardi
--  passa e vede se c'e' posto.
--
--  Il vincolo sta qui e non solo nell'app: una richiesta costruita
--  a mano riuscirebbe comunque a scavalcare i pulsanti.
--
--  Da eseguire nel SQL Editor DOPO 13.
-- ============================================================

alter table public.bookings
  add column if not exists dining_slot text not null default 'cena';

alter table public.bookings
  drop constraint if exists bookings_dining_slot_check;
alter table public.bookings
  add constraint bookings_dining_slot_check
  check (
    dining_slot in ('cena', 'cena_dopocena', 'dopocena')
    and (dining_slot <> 'dopocena' or booking_type = 'shared')
  );
