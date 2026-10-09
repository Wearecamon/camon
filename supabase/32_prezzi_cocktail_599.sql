-- ============================================================
--  CAMON · COCKTAIL A €5,99
--
--  Tutti i prodotti della categoria "cocktail" passano da €4,99
--  a €5,99. L'app legge i prezzi da qui (camonSyncMenu), quindi
--  basta lanciare questo file: il menu si aggiorna da solo alla
--  prossima apertura.
--
--  Lancialo in Supabase > SQL Editor. Alla fine mostra l'elenco
--  dei cocktail con il prezzo nuovo, per controllo.
-- ============================================================

update public.products
   set price_cents = 599
 where category = 'cocktail';

select name, price_cents
  from public.products
 where category = 'cocktail'
 order by sort;
