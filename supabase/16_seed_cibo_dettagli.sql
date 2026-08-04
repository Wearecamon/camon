-- ============================================================
--  CAMON · Dati dettaglio per i prodotti cibo
--  Popola ingredienti, allergeni, porzione, temperatura,
--  tempo di preparazione e flag dietetici.
--  Da eseguire DOPO 15.
-- ============================================================

-- ---- BURGER ------------------------------------------------

update public.products set
  ingredients    = 'Manzo 180g, cheddar, bacon croccante, lattuga, pomodoro, cipolla, salsa della casa',
  allergens      = array['glutine','latte','uova','sesamo'],
  portion_size   = '320 g',
  serving_temp   = 'caldo',
  prep_minutes   = 10,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'cheeseburger';

update public.products set
  ingredients    = 'Doppio manzo 200g, doppio bacon, doppio cheddar, salsa della casa',
  allergens      = array['glutine','latte','sesamo'],
  portion_size   = '420 g',
  serving_temp   = 'caldo',
  prep_minutes   = 12,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'double bacon';

update public.products set
  ingredients    = 'Petto di pollo croccante, lattuga iceberg, maionese, pomodoro',
  allergens      = array['glutine','uova','sesamo'],
  portion_size   = '300 g',
  serving_temp   = 'caldo',
  prep_minutes   = 10,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'chicken burger';

update public.products set
  ingredients    = 'Burger di legumi e verdure, lattuga, pomodoro, cipolla, salsa veg',
  allergens      = array['glutine','soia','sesamo'],
  portion_size   = '280 g',
  serving_temp   = 'caldo',
  prep_minutes   = 8,
  is_vegetarian  = true,
  is_vegan       = false,
  is_halal       = false
where name ilike 'veggie burger';

update public.products set
  ingredients    = 'Manzo 180g, cheddar, lattuga, pomodoro, salsa della casa, pane senza glutine',
  allergens      = array['latte','uova','sesamo'],
  portion_size   = '310 g',
  serving_temp   = 'caldo',
  prep_minutes   = 10,
  is_vegetarian  = false,
  is_gluten_free = true,
  is_halal       = false
where name ilike 'burger senza glutine';

update public.products set
  ingredients    = 'Piadina di farina, prosciutto crudo, squacquerone, rucola',
  allergens      = array['glutine','latte'],
  portion_size   = '250 g',
  serving_temp   = 'caldo',
  prep_minutes   = 5,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'piadina classica';

update public.products set
  ingredients    = 'Wurstel di maiale, pane morbido, senape, ketchup, cipolla',
  allergens      = array['glutine'],
  portion_size   = '210 g',
  serving_temp   = 'caldo',
  prep_minutes   = 4,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'hot dog';

-- ---- FRITTO ------------------------------------------------

update public.products set
  ingredients    = 'Patate, olio di girasole, sale, paprika affumicata',
  allergens      = array[]::text[],
  portion_size   = '150 g',
  serving_temp   = 'caldo',
  prep_minutes   = 6,
  is_vegetarian  = true,
  is_vegan       = true,
  is_gluten_free = true,
  is_halal       = true
where name ilike 'patatine' and category = 'fritto';

update public.products set
  ingredients    = 'Patate, salsa cheddar, bacon croccante, cipolla',
  allergens      = array['latte'],
  portion_size   = '200 g',
  serving_temp   = 'caldo',
  prep_minutes   = 7,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'patatine cheddar%';

update public.products set
  ingredients    = 'Alette di pollo, panatura di mais, salsa BBQ o piccante',
  allergens      = array['glutine'],
  portion_size   = '8 pezzi · 250 g',
  serving_temp   = 'caldo',
  prep_minutes   = 12,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'alette di pollo' and category = 'fritto';

update public.products set
  ingredients    = 'Petto di pollo, panatura, olio, salsa BBQ',
  allergens      = array['glutine','uova'],
  portion_size   = '8 pezzi · 200 g',
  serving_temp   = 'caldo',
  prep_minutes   = 8,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'nuggets%';

update public.products set
  ingredients    = 'Mozzarella fior di latte, panatura, olio di girasole',
  allergens      = array['glutine','latte'],
  portion_size   = '6 pezzi',
  serving_temp   = 'caldo',
  prep_minutes   = 7,
  is_vegetarian  = true,
  is_halal       = true
where name ilike 'mozzarella stick%';

update public.products set
  ingredients    = 'Peperoncini jalapeño, formaggio cremoso, panatura croccante',
  allergens      = array['glutine','latte'],
  portion_size   = '6 pezzi',
  serving_temp   = 'caldo',
  prep_minutes   = 7,
  is_vegetarian  = true,
  is_halal       = true
where name ilike 'jalapeño%';

update public.products set
  ingredients    = 'Cipolla, pastella di farina e birra, olio di girasole',
  allergens      = array['glutine'],
  portion_size   = '6 pezzi',
  serving_temp   = 'caldo',
  prep_minutes   = 6,
  is_vegetarian  = true,
  is_vegan       = true,
  is_halal       = true
where name ilike 'onion rings';

update public.products set
  ingredients    = 'Riso arborio, ragù di manzo o burro e mozzarella, panatura',
  allergens      = array['glutine','latte','uova'],
  portion_size   = '3 pezzi · 240 g',
  serving_temp   = 'caldo',
  prep_minutes   = 8,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'arancini';

-- ---- SPECIALE (senza glutine / veg) -------------------------

update public.products set
  ingredients    = 'Patate, olio di girasole, sale · friggitrice dedicata',
  allergens      = array[]::text[],
  portion_size   = '150 g',
  serving_temp   = 'caldo',
  prep_minutes   = 6,
  is_vegetarian  = true,
  is_vegan       = true,
  is_gluten_free = true,
  is_halal       = true
where name ilike 'patatine gf';

update public.products set
  ingredients    = 'Alette di pollo, salsa BBQ, spezie · non impanate',
  allergens      = array[]::text[],
  portion_size   = '250 g',
  serving_temp   = 'caldo',
  prep_minutes   = 12,
  is_vegetarian  = false,
  is_gluten_free = true,
  is_halal       = false
where name ilike 'alette di pollo gf';

-- ---- TAGLIERE ----------------------------------------------

update public.products set
  ingredients    = 'Fritti misti assortiti: alette, nuggets, mozzarella stick, onion rings',
  allergens      = array['glutine','latte','uova'],
  portion_size   = 'per 3-4 persone',
  serving_temp   = 'caldo',
  prep_minutes   = 15,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'camon box';

update public.products set
  ingredients    = 'Salumi misti (prosciutto crudo, salame, bresaola), formaggi stagionati, grissini',
  allergens      = array['glutine','latte'],
  portion_size   = 'per 2 persone',
  serving_temp   = 'ambiente',
  prep_minutes   = 5,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'tagliere misto';

update public.products set
  ingredients    = 'Chips di mais, avocado, lime, cipolla rossa, peperoncino, coriandolo, salsa pomodoro',
  allergens      = array[]::text[],
  portion_size   = '250 g',
  serving_temp   = 'ambiente',
  prep_minutes   = 3,
  is_vegetarian  = true,
  is_vegan       = true,
  is_gluten_free = true,
  is_halal       = true
where name ilike 'nachos%';

-- ---- PRIMO -------------------------------------------------

update public.products set
  ingredients    = 'Sfoglia all''uovo, ragù di manzo, besciamella, parmigiano reggiano',
  allergens      = array['glutine','latte','uova'],
  portion_size   = '350 g',
  serving_temp   = 'caldo',
  prep_minutes   = 12,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'lasagna';

update public.products set
  ingredients    = 'Pasta rigatoni, cheddar fuso, latte, burro, noce moscata',
  allergens      = array['glutine','latte'],
  portion_size   = '300 g',
  serving_temp   = 'caldo',
  prep_minutes   = 10,
  is_vegetarian  = true,
  is_halal       = true
where name ilike 'mac%cheese';

update public.products set
  ingredients    = 'Pasta, uova, guanciale, pecorino romano (carbonara) · oppure pomodoro, guanciale, pecorino (amatriciana)',
  allergens      = array['glutine','uova','latte'],
  portion_size   = '300 g',
  serving_temp   = 'caldo',
  prep_minutes   = 10,
  is_vegetarian  = false,
  is_halal       = false
where name ilike 'pasta del giorno';

-- ---- DOLCE -------------------------------------------------

update public.products set
  ingredients    = 'Cioccolato fondente 70%, farina, burro, uova, zucchero di canna',
  allergens      = array['glutine','latte','uova'],
  portion_size   = '90 g',
  serving_temp   = 'ambiente',
  prep_minutes   = 2,
  is_vegetarian  = true,
  is_halal       = true
where name ilike 'brownie' and not (name ilike '%vegano%');

update public.products set
  ingredients    = 'Farina di riso, cacao amaro, zucchero di canna, olio di cocco, latte di mandorla',
  allergens      = array['frutta a guscio'],
  portion_size   = '90 g',
  serving_temp   = 'ambiente',
  prep_minutes   = 2,
  is_vegetarian  = true,
  is_vegan       = true,
  is_gluten_free = true,
  is_halal       = true
where name ilike 'brownie vegano';

update public.products set
  ingredients    = 'Savoiardi, mascarpone, uova fresche, zucchero, caffè espresso, cacao amaro',
  allergens      = array['glutine','latte','uova'],
  portion_size   = '130 g',
  serving_temp   = 'freddo',
  prep_minutes   = 2,
  is_vegetarian  = true,
  is_halal       = true
where name ilike 'tiramisù';
