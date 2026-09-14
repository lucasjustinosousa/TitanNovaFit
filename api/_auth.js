// api/_auth.js
// Helpers reutilizáveis de autenticação, autorização e rate limiting para as Serverless Functions do TitanNova Fit.

/**
 * Extrai o Bearer token do cabeçalho de autorização da requisição HTTP
 */
export function extractBearerToken(req) {
  if (!req || !req.headers) return null;
  const authHeader = req.headers.authorization || req.headers.Authorization || '';
  if (typeof authHeader !== 'string') return null;
  const trimmed = authHeader.trim();
  if (trimmed.toLowerCase().startsWith('bearer ')) {
    const token = trimmed.substring(7).trim();
    return token.length > 0 ? token : null;
  }
  return null;
}

/**
 * Valida o token JWT diretamente no Supabase Auth
 */
export async function validateUserToken(token, supabaseUrl, serviceRoleKey) {
  if (!token || typeof token !== 'string' || !supabaseUrl || !serviceRoleKey) {
    return null;
  }

  try {
    const cleanUrl = supabaseUrl.replace(/\/+$/, '');
    const res = await fetch(`${cleanUrl}/auth/v1/user`, {
      method: 'GET',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${token}`,
      },
    });

    if (!res.ok) return null;
    const user = await res.json();
    if (!user || !user.id) return null;
    return user;
  } catch {
    return null;
  }
}

/**
 * Verifica se um usuário possui papel de Administrador ativo exclusivamente via banco de dados
 */
export async function verifyIsAdmin(userId, supabaseUrl, serviceRoleKey) {
  if (!userId || !supabaseUrl || !serviceRoleKey) return false;

  try {
    const cleanUrl = supabaseUrl.replace(/\/+$/, '');

    // 1. Checar user_roles com active = true e role = admin
    const rolesRes = await fetch(
      `${cleanUrl}/rest/v1/user_roles?user_id=eq.${encodeURIComponent(userId)}&role=eq.admin&active=eq.true&select=id`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      }
    );

    if (rolesRes.ok) {
      const roles = await rolesRes.json();
      if (Array.isArray(roles) && roles.length > 0) return true;
    }

    // 2. Fallback de compatibilidade em admin_users
    const adminRes = await fetch(
      `${cleanUrl}/rest/v1/admin_users?user_id=eq.${encodeURIComponent(userId)}&select=user_id`,
      {
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      }
    );

    if (adminRes.ok) {
      const admins = await adminRes.json();
      if (Array.isArray(admins) && admins.length > 0) return true;
    }

    return false;
  } catch {
    return false;
  }
}

/**
 * Exige usuário autenticado. Retorna { user, errorResponse }
 */
export async function requireAuth(req, supabaseUrl, serviceRoleKey) {
  const token = extractBearerToken(req);
  if (!token) {
    return {
      user: null,
      errorResponse: { status: 401, body: { error: 'Token de autenticação obrigatório.' } },
    };
  }

  const user = await validateUserToken(token, supabaseUrl, serviceRoleKey);
  if (!user) {
    return {
      user: null,
      errorResponse: { status: 401, body: { error: 'Sessão inválida, expirada ou não autorizada.' } },
    };
  }

  return { user, errorResponse: null };
}

/**
 * Exige usuário autenticado E com papel de administrador ativo. Retorna { adminUser, errorResponse }
 */
export async function requireAdmin(req, supabaseUrl, serviceRoleKey) {
  const { user, errorResponse } = await requireAuth(req, supabaseUrl, serviceRoleKey);
  if (errorResponse) {
    return { adminUser: null, errorResponse };
  }

  const isAdmin = await verifyIsAdmin(user.id, supabaseUrl, serviceRoleKey);
  if (!isAdmin) {
    return {
      adminUser: null,
      errorResponse: { status: 403, body: { error: 'Acesso negado: permissão de Administrador requerida.' } },
    };
  }

  return { adminUser: user, errorResponse: null };
}

/**
 * Resposta padronizada compatível com Vercel Node.js Runtime e Edge Runtime
 */
export function sendStandardResponse(res, statusCode, data, corsHeaders = {}) {
  if (res && typeof res.status === 'function') {
    return res.status(statusCode).json(data);
  }
  return new Response(JSON.stringify(data), {
    status: statusCode,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/**
 * Rate Limiting simples em memória para mitigar abusos por IP/identificador
 */
const rateLimitMap = new Map();
const RATE_LIMIT_CLEANUP_INTERVAL = 60000;
let lastCleanup = Date.now();

export function checkRateLimit(key, maxRequests = 30, windowMs = 60000) {
  const now = Date.now();
  if (now - lastCleanup > RATE_LIMIT_CLEANUP_INTERVAL) {
    for (const [k, v] of rateLimitMap.entries()) {
      if (now - v.startTime > windowMs) {
        rateLimitMap.delete(k);
      }
    }
    lastCleanup = now;
  }

  const record = rateLimitMap.get(key) || { count: 0, startTime: now };
  if (now - record.startTime > windowMs) {
    record.count = 1;
    record.startTime = now;
    rateLimitMap.set(key, record);
    return true;
  }

  record.count += 1;
  rateLimitMap.set(key, record);
  return record.count <= maxRequests;
}
