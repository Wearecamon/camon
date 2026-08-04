-- ============================================================
--  CAMON · CAMPI EXTRA PER IL CIBO
--  Aggiunge porzione, temperatura di servizio, vegetariano e halal
--  alla tabella products. Da eseguire nel SQL Editor DOPO 14.
-- ============================================================

alter table public.products
  add column if not exists portion_size   text,          -- es. "250 g", "1 pezzo"
  add column if not exists serving_temp   text           -- 'caldo' | 'freddo' | 'ambiente'
    check (serving_temp in ('caldo','freddo','ambiente')),
  add column if not exists is_vegetarian  boolean not null default false,
  add column if not exists is_halal       boolean not null default false;

-- ------------------------------------------------------------
--  Esempio: come si compila una scheda cibo.
--  Togli il commento e adatta il nome per provare.
-- ------------------------------------------------------------
-- update public.products set
--   description    = 'Hamburger con manzo 200g, cheddar, insalata, pomodoro e salsa speciale.',
--   ingredients    = 'Manzo, cheddar, lattuga, pomodoro, cipolla, salsa speciale, pane brioche',
--   allergens      = array['glutine','latte','sesamo'],
--   portion_size   = '350 g',
--   serving_temp   = 'caldo',
--   prep_minutes   = 10,
--   is_vegetarian  = false,
--   is_halal       = false,
--   is_gluten_free = false
-- where name ilike 'hamburger%';
