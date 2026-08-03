-- ============================================================
--  CAMON · SCHEDE PRODOTTO PIU' COMPLETE
--  La tabella aveva solo nome, prezzo e una descrizione: troppo
--  poco per una scheda che deve informare il cliente. Qui si
--  aggiunge il resto, allergeni inclusi — che per la ristorazione
--  vanno indicati per obbligo di legge.
--
--  Da eseguire nel SQL Editor DOPO 12.
-- ============================================================

alter table public.products
  add column if not exists ingredients   text,     -- "Gin, tonica, lime"
  add column if not exists allergens     text[],   -- {glutine,latte}
  add column if not exists abv           numeric(4,1),  -- gradazione: 12.5
  add column if not exists volume_ml     integer,  -- 200
  add column if not exists origin        text,     -- produttore o provenienza
  add column if not exists is_vegan      boolean not null default false,
  add column if not exists is_gluten_free boolean not null default false,
  add column if not exists is_signature  boolean not null default false,  -- "la casa consiglia"
  add column if not exists prep_minutes  integer;  -- attesa indicativa

-- Lo staff modifica le schede dall'area titolare
drop policy if exists "prodotti: staff aggiorna" on public.products;
create policy "prodotti: staff aggiorna" on public.products
  for update using (public.is_staff());

-- ------------------------------------------------------------
--  Esempio: come si compila una scheda.
--  Togli il commento e adatta il nome per provare.
-- ------------------------------------------------------------
-- update public.products set
--   description    = 'Il nostro classico, con prosecco di Valdobbiadene e una fetta d''arancia.',
--   ingredients    = 'Prosecco, Aperol, soda, arancia',
--   allergens      = array['solfiti'],
--   abv            = 8.0,
--   volume_ml      = 200,
--   origin         = 'Bar CAMON',
--   is_vegan       = true,
--   is_gluten_free = true,
--   is_signature   = true,
--   prep_minutes   = 3
-- where name ilike 'spritz%';
