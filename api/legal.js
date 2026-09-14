import { getSupabaseServerConfig, createCorsHeaders } from './_config.js';

export default async function handler(req, res) {
  const origin = req.headers?.origin || '*';
  const corsHeaders = createCorsHeaders(origin, 'GET, OPTIONS, POST');
  if (res && typeof res.setHeader === 'function') {
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    Object.entries(corsHeaders).forEach(([k, v]) => res.setHeader(k, v));
  }

  if (req.method === 'OPTIONS') {
    if (res && typeof res.status === 'function') {
      return res.status(200).end();
    }
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  const config = getSupabaseServerConfig();
  if (!config.isValid) {
    if (res && typeof res.status === 'function') {
      return res.status(500).json({ error: config.error });
    }
    return new Response(JSON.stringify({ error: config.error }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  const { supabaseUrl: SUPABASE_URL, serviceRoleKey: SUPABASE_SERVICE_ROLE } = config;

  // 1. GET: Consultar status de aceite do usuário
  if (req.method === 'GET') {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({ error: 'Parâmetro userId obrigatório.' });
    }

    try {
      const resp = await fetch(
        `${SUPABASE_URL}/rest/v1/legal_acceptances?user_id=eq.${encodeURIComponent(userId)}&order=accepted_at.desc&limit=1`,
        {
          headers: {
            'apikey': SUPABASE_SERVICE_ROLE,
            'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE}`
          }
        }
      );

      if (resp.ok) {
        const records = await resp.json();
        return res.status(200).json({
          hasAccepted: records.length > 0,
          latest: records[0] || null
        });
      } else {
        return res.status(200).json({ hasAccepted: false, note: 'Tabela ainda sendo inicializada' });
      }
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  // 2. POST: Gravar aceite de Termos e Privacidade
  if (req.method === 'POST') {
    const body = req.body || {};
    const {
      user_id,
      terms_version = "1.0",
      privacy_version = "1.0",
      terms_accepted = true,
      privacy_acknowledged = true,
      age_requirement_confirmed = true,
      guardian_authorization_confirmed = true,
      analytics_consent = false,
      platform = 'web',
      language = 'pt-BR'
    } = body;

    if (!user_id) {
      return res.status(400).json({ error: 'user_id é obrigatório para registrar aceite legal.' });
    }

    try {
      const resp = await fetch(
        `${SUPABASE_URL}/rest/v1/legal_acceptances`,
        {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_SERVICE_ROLE,
            'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
          },
          body: JSON.stringify({
            user_id,
            terms_version,
            privacy_version,
            terms_accepted: Boolean(terms_accepted),
            privacy_acknowledged: Boolean(privacy_acknowledged),
            age_requirement_confirmed: Boolean(age_requirement_confirmed),
            guardian_authorization_confirmed: Boolean(guardian_authorization_confirmed),
            analytics_consent: Boolean(analytics_consent),
            platform: String(platform).substring(0, 100),
            language: String(language).substring(0, 10)
          })
        }
      );

      if (!resp.ok) {
        const txt = await resp.text();
        console.warn('[API Legal Insert Notice]:', resp.status, txt);
      }

      return res.status(200).json({
        success: true,
        recorded_at: new Date().toISOString()
      });
    } catch (err) {
      return res.status(200).json({ success: true, localOnly: true, error: err.message });
    }
  }

  return res.status(405).json({ error: 'Método não permitido.' });
}
