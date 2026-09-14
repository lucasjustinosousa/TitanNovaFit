// api/legal.js — TitanNova Fit Legal & Privacy API (LGPD)
// Registra e verifica aceites legais de Termos e Privacidade de forma estritamente autenticada
import { getSupabaseServerConfig, createCorsHeaders } from './_config.js';
import { requireAuth, sendStandardResponse, checkRateLimit } from './_auth.js';

export default async function handler(req, res) {
  const origin = req.headers?.origin || '*';
  const corsHeaders = createCorsHeaders(origin, 'GET, POST, OPTIONS');

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
    return sendStandardResponse(res, 500, { error: config.error }, corsHeaders);
  }
  const { supabaseUrl: SUPABASE_URL, serviceRoleKey: SUPABASE_SERVICE_ROLE } = config;

  // Rate Limiting defensivo por IP
  const clientIp = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown';
  if (!checkRateLimit(`legal:${clientIp}`, 60, 60000)) {
    return sendStandardResponse(res, 429, { error: 'Muitas requisições. Tente novamente mais tarde.' }, corsHeaders);
  }

  // 1. EXIGIR AUTENTICAÇÃO OBRIGATÓRIA (Bearer Token)
  const { user, errorResponse } = await requireAuth(req, SUPABASE_URL, SUPABASE_SERVICE_ROLE);
  if (errorResponse) {
    return sendStandardResponse(res, errorResponse.status, errorResponse.body, corsHeaders);
  }

  const authenticatedUserId = user.id;

  // 2. GET: Consultar status de aceite legal do usuário autenticado
  if (req.method === 'GET') {
    try {
      const resp = await fetch(
        `${SUPABASE_URL}/rest/v1/legal_acceptances?user_id=eq.${encodeURIComponent(authenticatedUserId)}&order=accepted_at.desc&limit=1`,
        {
          headers: {
            apikey: SUPABASE_SERVICE_ROLE,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE}`,
          },
        }
      );

      if (!resp.ok) {
        return sendStandardResponse(res, 500, { error: 'Falha ao consultar registros legais.' }, corsHeaders);
      }

      const records = await resp.json();
      return sendStandardResponse(res, 200, {
        hasAccepted: records.length > 0,
        latest: records[0] || null,
      }, corsHeaders);
    } catch {
      return sendStandardResponse(res, 500, { error: 'Erro interno ao consultar aceites legais.' }, corsHeaders);
    }
  }

  // 3. POST: Gravar aceite de Termos e Privacidade para o usuário autenticado
  if (req.method === 'POST') {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});

    // Validação de tipos e limites dos campos
    const termsVersion = String(body.terms_version || '1.0').trim().substring(0, 20);
    const privacyVersion = String(body.privacy_version || '1.0').trim().substring(0, 20);
    const termsAccepted = Boolean(body.terms_accepted);
    const privacyAcknowledged = Boolean(body.privacy_acknowledged);
    const ageRequirementConfirmed = Boolean(body.age_requirement_confirmed);
    const guardianAuthorizationConfirmed = Boolean(body.guardian_authorization_confirmed);
    const analyticsConsent = Boolean(body.analytics_consent);
    const platform = String(body.platform || 'web').trim().substring(0, 50);
    const language = String(body.language || 'pt-BR').trim().substring(0, 10);

    if (!termsAccepted || !privacyAcknowledged || !ageRequirementConfirmed) {
      return sendStandardResponse(res, 400, {
        error: 'É obrigatório aceitar os Termos de Uso, a Política de Privacidade e confirmar o requisito de idade mínima.',
      }, corsHeaders);
    }

    try {
      const resp = await fetch(`${SUPABASE_URL}/rest/v1/legal_acceptances`, {
        method: 'POST',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify({
          user_id: authenticatedUserId, // IGNORA user_id externo do cliente!
          terms_version: termsVersion,
          privacy_version: privacyVersion,
          terms_accepted: termsAccepted,
          privacy_acknowledged: privacyAcknowledged,
          age_requirement_confirmed: ageRequirementConfirmed,
          guardian_authorization_confirmed: guardianAuthorizationConfirmed,
          analytics_consent: analyticsConsent,
          platform: platform,
          language: language,
        }),
      });

      if (!resp.ok) {
        return sendStandardResponse(res, resp.status, { error: 'Falha ao registrar aceite legal no banco de dados.' }, corsHeaders);
      }

      const inserted = await resp.json();
      return sendStandardResponse(res, 200, {
        success: true,
        recorded_at: (inserted && inserted[0] && inserted[0].accepted_at) || new Date().toISOString(),
      }, corsHeaders);
    } catch {
      return sendStandardResponse(res, 500, { error: 'Erro interno ao processar registro legal.' }, corsHeaders);
    }
  }

  return sendStandardResponse(res, 405, { error: 'Método não permitido.' }, corsHeaders);
}
