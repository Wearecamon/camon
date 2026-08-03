// ============================================================
//  CAMON · Avviso email per le richieste di festa privata
//
//  Si attiva da sola a ogni nuova riga in event_requests e manda
//  una mail al locale, cosi' non serve tenere d'occhio la dashboard.
//
//  Per attivarla servono, dal tuo account:
//   1. Un account su https://resend.com (gratuito fino a 100 mail
//      al giorno) e un dominio verificato, oppure il mittente di
//      prova onboarding@resend.dev.
//   2. Le due variabili, dal pannello Supabase:
//        supabase secrets set RESEND_API_KEY=re_xxxxxxxx
//        supabase secrets set CAMON_EMAIL=tua@email.it
//   3. Il rilascio:
//        supabase functions deploy avviso-festa --no-verify-jwt
//   4. Il collegamento alla tabella: vedi 11_avviso_festa.sql
// ============================================================

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const CAMON_EMAIL    = Deno.env.get('CAMON_EMAIL');
const MITTENTE       = Deno.env.get('CAMON_FROM') ?? 'CAMON <onboarding@resend.dev>';

function esc(v: unknown): string {
  return String(v ?? '—').replace(/[&<>]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string));
}

Deno.serve(async (req) => {
  if (!RESEND_API_KEY || !CAMON_EMAIL) {
    // Meglio fallire qui che far finta: senza chiavi non parte nulla
    return new Response('RESEND_API_KEY o CAMON_EMAIL non configurate', { status: 500 });
  }

  try {
    const body = await req.json();
    const r = body.record ?? body;   // il webhook incapsula la riga in "record"

    const quando = r.event_date
      ? new Date(r.event_date).toLocaleDateString('it-IT',
          { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
      : '—';

    const html = `
      <div style="font-family:system-ui,sans-serif;max-width:520px;color:#111">
        <h2 style="margin:0 0 4px">Nuova richiesta di festa privata</h2>
        <p style="color:#666;margin:0 0 18px">Arrivata da CAMON</p>
        <table cellpadding="7" style="border-collapse:collapse;width:100%;font-size:14px">
          <tr><td><b>Cliente</b></td><td>${esc(r.full_name)}</td></tr>
          <tr><td><b>Telefono</b></td><td><a href="tel:${esc(r.phone)}">${esc(r.phone)}</a></td></tr>
          <tr><td><b>Email</b></td><td><a href="mailto:${esc(r.email)}">${esc(r.email)}</a></td></tr>
          <tr><td><b>Quando</b></td><td>${esc(quando)} ${esc(r.event_time ?? '')}</td></tr>
          <tr><td><b>Occasione</b></td><td>${esc(r.occasion)}</td></tr>
          <tr><td><b>Atmosfera</b></td><td>${esc(r.mood)}</td></tr>
          <tr><td><b>Invitati</b></td><td>${esc(r.guests)}</td></tr>
        </table>
        ${r.notes ? `<div style="margin-top:16px">
          <b style="font-size:14px">Come immagina la serata</b>
          <p style="background:#f4f4f5;padding:13px;border-radius:9px;font-size:14px;line-height:1.55;white-space:pre-wrap">${esc(r.notes)}</p>
        </div>` : ''}
        <p style="color:#666;font-size:13px;margin-top:18px">
          Il cliente si aspetta una risposta entro 24 ore.
        </p>
      </div>`;

    const risposta = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: MITTENTE,
        to: [CAMON_EMAIL],
        reply_to: r.email,          // rispondendo si scrive al cliente
        subject: `Festa privata · ${r.full_name} · ${quando}`,
        html,
      }),
    });

    if (!risposta.ok) {
      return new Response(`Invio fallito: ${await risposta.text()}`, { status: 502 });
    }
    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(`Errore: ${e instanceof Error ? e.message : e}`, { status: 400 });
  }
});
