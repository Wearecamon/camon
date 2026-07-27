# Shot IQ — Argomento libero (AI) · Setup weekend

Generazione domande trivia su misura tramite **Claude Haiku 4.5**.

## Cosa c'è già pronto
- **Frontend** (in `camon.html`): card "✏️ Argomento libero" nel gioco Shot IQ, campo di testo, esempi rapidi, stati di caricamento/errore. Già pronto a chiamare il backend.
- **Backend** (`api/shotiq.js`): funzione serverless che chiama Claude e restituisce le domande in JSON. Include CORS e una cache in memoria.

## Da fare nel weekend (3 passi)

### 1. Deploy del backend
Carica la cartella su **Vercel** (consigliato, gratis):
```
npm i -g vercel
cd "Nuova cartella (6)"
vercel
```
La funzione sarà disponibile su `https://<tuo-progetto>.vercel.app/api/shotiq`.

### 2. Imposta la API key
Su Vercel → Project → Settings → Environment Variables:
```
ANTHROPIC_API_KEY = sk-ant-xxxxxxxx
```
(la ottieni da console.anthropic.com). **Non** va mai messa nel file HTML.

### 3. Collega il frontend
In `camon.html`, cerca `SIQ_API_URL` e incolla l'URL:
```js
const SIQ_API_URL = 'https://<tuo-progetto>.vercel.app/api/shotiq';
```

Fatto. Da quel momento il campo "Argomento libero" funziona.

## Costi
Con Haiku 4.5 ~0,3–0,5 centesimi a partita. La cache riduce ulteriormente: argomenti
già richiesti vengono riusati senza richiamare l'AI. Per una cache permanente
(tra riavvii del server) sostituire l'oggetto `cache` con un KV store (es. Vercel KV / Upstash Redis).

## Formato API
**Richiesta** `POST /api/shotiq`
```json
{ "topic": "Basket NBA" }
```
**Risposta**
```json
{ "questions": [ { "q": "Quante squadre ci sono in NBA?", "a": "30" }, ... ] }
```
