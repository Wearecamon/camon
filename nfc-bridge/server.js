// ============================================================
//  CAMON · NFC Bridge
//  Legge l'UID dalla tessera tramite ACR122U e lo manda via
//  WebSocket al totem (totem.html).
//
//  AVVIO:
//    1. npm install
//    2. copia .env.example in .env e compila i valori
//    3. node server.js
//
//  Il totem si connette a ws://localhost:8765
// ============================================================

require('dotenv').config();
const { NFC }      = require('nfc-pcsc');
const { WebSocketServer } = require('ws');

const WS_PORT         = parseInt(process.env.WS_PORT || '8765');
const SUPABASE_URL    = process.env.SUPABASE_URL;
const SUPABASE_KEY    = process.env.SUPABASE_SERVICE_KEY;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('❌  Mancano SUPABASE_URL o SUPABASE_SERVICE_KEY nel file .env');
  process.exit(1);
}

// ── WebSocket server ──────────────────────────────────────────
const wss = new WebSocketServer({ port: WS_PORT });
const clients = new Set();

wss.on('connection', ws => {
  clients.add(ws);
  console.log(`🟢 Totem connesso (${clients.size} client attivi)`);
  ws.send(JSON.stringify({ type: 'ready', message: 'Bridge NFC connesso' }));

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`🔴 Totem disconnesso (${clients.size} client attivi)`);
  });
});

function broadcast(obj) {
  const msg = JSON.stringify(obj);
  for (const ws of clients) {
    if (ws.readyState === 1) ws.send(msg);
  }
}

// ── Supabase helper (fetch puro, nessuna libreria extra) ──────
async function supabaseRpc(fn, params) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'apikey':        SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
    },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (!res.ok) {
    // Supabase mette il messaggio di errore in data.message o data.hint
    throw new Error(data.message || data.hint || JSON.stringify(data));
  }
  return data;
}

// ── NFC reader ────────────────────────────────────────────────
const nfc = new NFC();

nfc.on('reader', reader => {
  console.log(`📡 Lettore NFC rilevato: ${reader.name}`);
  broadcast({ type: 'reader_connected', reader: reader.name });

  reader.on('card', async card => {
    // L'UID arriva come Buffer; lo convertiamo in stringa esadecimale maiuscola
    const uid = card.uid.toUpperCase();
    console.log(`💳 Carta rilevata: ${uid}`);

    // 1. Manda subito l'UID al totem — lui decide cosa farne
    broadcast({ type: 'card', uid });

    // 2. Lookup automatico: trova utente + saldo
    try {
      const rows = await supabaseRpc('nfc_lookup', { p_uid: uid });
      if (rows && rows.length > 0) {
        const user = rows[0];
        broadcast({
          type:          'user_identified',
          uid,
          user_id:       user.user_id,
          first_name:    user.first_name || '',
          last_name:     user.last_name  || '',
          balance_cents: user.balance_cents,
        });
        console.log(`✅ Utente: ${user.first_name} ${user.last_name} · Saldo: €${(user.balance_cents/100).toFixed(2)}`);
      } else {
        broadcast({ type: 'card_unknown', uid });
        console.log(`⚠️  Carta non registrata: ${uid}`);
      }
    } catch (err) {
      const msg = err.message || String(err);
      if (msg === 'CARD_NOT_FOUND') {
        broadcast({ type: 'card_unknown', uid });
        console.log(`⚠️  Carta non registrata: ${uid}`);
      } else {
        broadcast({ type: 'error', message: msg });
        console.error(`❌ Errore lookup: ${msg}`);
      }
    }
  });

  reader.on('card.off', () => {
    broadcast({ type: 'card_removed' });
    console.log('🔲 Carta rimossa');
  });

  reader.on('error', err => {
    console.error(`Errore reader: ${err.message}`);
  });
});

nfc.on('error', err => {
  console.error(`Errore NFC: ${err.message}`);
  broadcast({ type: 'error', message: err.message });
});

console.log(`🚀 Bridge NFC avviato — in ascolto su ws://localhost:${WS_PORT}`);
console.log('   Collega l\'ACR122U via USB e avvicina una tessera.');
