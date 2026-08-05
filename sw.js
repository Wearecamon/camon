/* Service worker CAMON — network-first per la pagina principale.
   Ogni apertura del bookmark prova a caricare la versione aggiornata
   dalla rete; se non c'è connessione usa quella in cache. */

const CACHE = 'camon-v2';

/* Attiva subito, ma NON ruba il controllo delle pagine già aperte
   (niente clients.claim): così il reload automatico in-page si attiva
   solo quando c'era già un SW precedente, non al primo avvio. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;

  /* Solo richieste GET — le chiamate Supabase (POST/PATCH…) passano direttamente. */
  if (req.method !== 'GET') return;

  /* URL esterni (Supabase, CDN font, ecc.) — cache-first breve per le risorse
     statiche, nessuna cache per le API. */
  const url = new URL(req.url);
  const isNavigation = req.mode === 'navigate';
  const isSameOrigin = url.origin === self.location.origin;
  const isApi = url.hostname.includes('supabase');

  if (isApi) return; /* le chiamate al backend passano sempre dalla rete */

  if (isNavigation || isSameOrigin) {
    /* Network-first: prova la rete, aggiorna la cache, ritorna la risposta.
       Se la rete fallisce usa la cache. */
    e.respondWith(
      fetch(req)
        .then(res => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put(req, copy));
          }
          return res;
        })
        .catch(() => caches.match(req))
    );
  } else {
    /* Risorse esterne (font, ecc.) — cache-first. */
    e.respondWith(
      caches.match(req).then(cached => {
        if (cached) return cached;
        return fetch(req).then(res => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put(req, copy));
          }
          return res;
        });
      })
    );
  }
});
