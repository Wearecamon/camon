// ============================================================
//  SHOT IQ — Backend generazione domande (Claude Haiku 4.5)
// ============================================================
//
// Funzione serverless stile Vercel (cartella /api).
// Riceve { topic: "Basket NBA" } e restituisce
//   { questions: [ { q: "...", a: "..." }, ... ] }
//
// ---- SETUP (nel weekend) -----------------------------------
// 1. Deploya questa cartella su Vercel (o Netlify/Cloudflare).
// 2. Imposta la variabile d'ambiente:  ANTHROPIC_API_KEY = sk-ant-...
// 3. Copia l'URL pubblico (es. https://camon.vercel.app/api/shotiq)
//    e incollalo in camon.html nella costante  SIQ_API_URL.
// ------------------------------------------------------------

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5-20251001'; // veloce ed economico, perfetto per il trivia

// piccola cache in memoria: stesso argomento → niente nuova chiamata
// (su serverless dura finché l'istanza resta "calda"; per cache vera usa un DB/KV)
const cache = {};

export default async function handler(req, res) {
  // CORS — permette alla web app di chiamare il backend
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const topic = (body.topic || '').toString().trim().slice(0, 60);
    if (!topic) return res.status(400).json({ error: 'Topic mancante' });

    // cache hit
    const cacheKey = topic.toLowerCase();
    if (cache[cacheKey]) return res.status(200).json({ questions: cache[cacheKey], cached: true });

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) return res.status(500).json({ error: 'API key non configurata sul server' });

    const prompt = `Genera esattamente 10 domande di trivia in ITALIANO sull'argomento: "${topic}".
Regole:
- Domande di difficoltà media, adatte a un gioco da bar tra amici.
- Ogni domanda deve avere UNA risposta breve e inequivocabile.
- Niente domande offensive o pericolose.
- Rispondi SOLO con un array JSON valido, senza testo aggiuntivo, in questo formato:
[{"q":"testo domanda","a":"risposta breve"}, ...]`;

    const aiRes = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1500,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    if (!aiRes.ok) {
      const errTxt = await aiRes.text();
      return res.status(502).json({ error: 'Errore AI', detail: errTxt });
    }

    const data = await aiRes.json();
    const text = (data.content && data.content[0] && data.content[0].text) || '';

    // estrai l'array JSON dalla risposta del modello
    let questions = [];
    try {
      const match = text.match(/\[[\s\S]*\]/);
      questions = JSON.parse(match ? match[0] : text);
    } catch (e) {
      return res.status(502).json({ error: 'Risposta AI non valida', raw: text });
    }

    // pulizia minima
    questions = questions
      .filter(function (it) { return it && it.q && it.a; })
      .map(function (it) { return { q: String(it.q), a: String(it.a) }; })
      .slice(0, 10);

    if (!questions.length) return res.status(502).json({ error: 'Nessuna domanda generata' });

    cache[cacheKey] = questions; // salva in cache
    return res.status(200).json({ questions: questions });
  } catch (e) {
    return res.status(500).json({ error: 'Errore interno', detail: String(e) });
  }
}
