import { getSupabaseServerConfig, createCorsHeaders } from "./_config.js";
import { requireAdmin, checkRateLimit, sendStandardResponse } from "./_auth.js";

export default async function handler(req, res) {
  const origin = req.headers?.origin || "*";
  const corsHeaders = createCorsHeaders(origin, "GET, POST, DELETE, OPTIONS");

  if (req.method === "OPTIONS") {
    if (res && typeof res.writeHead === "function") {
      res.writeHead(204, corsHeaders);
      res.end();
      return;
    }
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const sendResponse = (statusCode, data) => {
    return sendStandardResponse(res, statusCode, data, corsHeaders);
  };

  const config = getSupabaseServerConfig();
  if (!config.isValid) {
    return sendResponse(500, { error: config.error });
  }
  const { supabaseUrl: SUPABASE_URL, serviceRoleKey: SERVICE_ROLE_KEY } = config;

  // Rate Limiting para endpoints administrativos
  const clientIp = req.headers?.['x-forwarded-for'] || req.socket?.remoteAddress || 'admin-client';
  if (!checkRateLimit(`admin:${clientIp}`, 100, 60000)) {
    return sendResponse(429, { error: "Muitas requisições. Tente novamente mais tarde." });
  }

  // Validação estrita de sessão e papel de Administrador
  const { adminUser: callerUser, errorResponse } = await requireAdmin(req, SUPABASE_URL, SERVICE_ROLE_KEY);
  if (errorResponse) {
    return sendResponse(errorResponse.status, errorResponse.body);
  }

  // Helper para auditoria
  const logAudit = async (action, targetType, targetId, prevData, newData) => {
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/admin_audit_logs`, {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          admin_user_id: callerUser.id,
          action,
          target_type: targetType,
          target_id: targetId,
          previous_data: prevData || null,
          new_data: newData || null
        })
      });
    } catch (_) {}
  };

  // ==============================================================================
  // GET: Listagem e pesquisa de usuários com papéis e planos
  // ==============================================================================
  if (req.method === "GET") {
    try {
      const queryParam = (req.query?.q || "").toLowerCase().trim();

      // Consultar auth.users via API administrativa
      const authResp = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?per_page=100`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });

      if (!authResp.ok) throw new Error("Falha ao consultar usuários no Supabase.");

      const authData = await authResp.json();
      const rawUsers = authData.users || [];

      // Buscar papéis de todos os usuários
      const rolesRes = await fetch(`${SUPABASE_URL}/rest/v1/user_roles?select=user_id,role,active`, {
        headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` }
      });
      const allRoles = rolesRes.ok ? await rolesRes.json() : [];

      // Buscar assinaturas
      const subsRes = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?select=user_id,plan_id,status,current_period_end`, {
        headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` }
      });
      const allSubs = subsRes.ok ? await subsRes.json() : [];

      const formatted = rawUsers.map(u => {
        const meta = u.user_metadata || {};
        const email = u.email || "";
        const nome = meta.nome || email.split("@")[0] || "Usuário";
        const userRoles = allRoles.filter(r => r.user_id === u.id);
        const primaryRole = userRoles.find(r => r.active)?.role || meta.account_type || "athlete";
        const isSuspended = userRoles.some(r => !r.active && r.role === primaryRole);
        const sub = allSubs.find(s => s.user_id === u.id);
        const planCode = primaryRole === "admin" ? null : (sub?.plan_id || "free");

        return {
          id: u.id,
          nome,
          email,
          role: primaryRole,
          plan: planCode,
          subscription_status: sub?.status || "active",
          is_suspended: isSuspended,
          created_at: u.created_at,
          last_sign_in: u.last_sign_in_at
        };
      }).filter(u => {
        if (!queryParam) return true;
        return u.nome.toLowerCase().includes(queryParam) || u.email.toLowerCase().includes(queryParam) || u.role.includes(queryParam);
      });

      return sendResponse(200, { success: true, users: formatted, total: formatted.length });
    } catch (err) {
      return sendResponse(500, { error: err.message });
    }
  }

  // ==============================================================================
  // POST: Ações administrativas sobre usuários (Suspender / Reativar)
  // ==============================================================================
  if (req.method === "POST") {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : (req.body || {});
    const action = body.action || req.query?.action;
    const targetUserId = body.userId || body.target_user_id;

    if (!targetUserId) {
      return sendResponse(400, { error: "target_user_id obrigatório." });
    }

    if (action === "toggle_suspend") {
      const suspend = Boolean(body.suspend);

      // Não permitir suspender a si mesmo ou a outro admin
      if (targetUserId === callerUser.id) {
        return sendResponse(400, { error: "Você não pode suspender sua própria conta de Administrador." });
      }

      try {
        await fetch(`${SUPABASE_URL}/rest/v1/user_roles?user_id=eq.${encodeURIComponent(targetUserId)}`, {
          method: "PATCH",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ active: !suspend })
        });

        await logAudit(suspend ? "user_suspended" : "user_reactivated", "user", targetUserId, null, { suspended: suspend });

        return sendResponse(200, {
          success: true,
          message: `Usuário ${suspend ? "suspenso" : "reativado"} com sucesso.`
        });
      } catch (err) {
        return sendResponse(500, { error: err.message });
      }
    }

    return sendResponse(400, { error: "Ação não suportada." });
  }

  // ==============================================================================
  // DELETE: Exclusão administrativa (somente com confirmação)
  // ==============================================================================
  if (req.method === "DELETE") {
    const userId = (req.query && req.query.userId) || (req.body && req.body.userId);
    if (!userId) return sendResponse(400, { error: "userId obrigatório." });

    if (userId === callerUser.id) {
      return sendResponse(400, { error: "Não é permitido excluir a própria conta de administrador." });
    }

    try {
      // Excluir do Supabase Auth
      await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
        method: "DELETE",
        headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` }
      });

      await logAudit("user_deleted", "user", userId, null, { deleted_at: new Date().toISOString() });

      return sendResponse(200, { success: true, message: "Usuário excluído com sucesso." });
    } catch (err) {
      return sendResponse(500, { error: err.message });
    }
  }

  return sendResponse(405, { error: "Método não permitido." });
}
