// api/_config.js
// Configuração segura e centralizada para as Serverless Functions do TitanNova Fit.
// Garante o uso exclusivo de variáveis de ambiente sem fallbacks codificados ou inseguros.

export function getSupabaseServerConfig() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (
    !supabaseUrl ||
    typeof supabaseUrl !== 'string' ||
    supabaseUrl.trim() === '' ||
    !serviceRoleKey ||
    typeof serviceRoleKey !== 'string' ||
    serviceRoleKey.trim() === ''
  ) {
    return {
      isValid: false,
      error: 'Serviço temporariamente indisponível. Erro de configuração do servidor.',
      supabaseUrl: null,
      serviceRoleKey: null,
    };
  }

  return {
    isValid: true,
    error: null,
    supabaseUrl: supabaseUrl.trim().replace(/\/+$/, ''),
    serviceRoleKey: serviceRoleKey.trim(),
  };
}

export function createCorsHeaders(origin = '*', methods = 'GET, POST, OPTIONS') {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': methods,
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With, Accept, X-Api-Version, X-CSRF-Token',
  };
}
