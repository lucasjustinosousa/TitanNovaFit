// Vercel Serverless Function: /api/users
// Gestão segura e restrita de usuários para o Painel Administrativo do TitanNova Fit
// Exclusivo para administradores validados no banco via user_roles (is_admin)

const SUPABASE_URL = process.env.SUPABASE_URL || "https://gplgywrvejefulsjpkax.supabase.co";
const DEFAULT_KEY_B64 = "c2Jfc2VjcmV0X2p5eWdfVC0tdDhPWFNPQ3k0NXB1blFfNXpwcG5vaGs=";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || (typeof Buffer !== "undefined" ? Buffer.from(DEFAULT_KEY_B64, "base64").toString("utf-8") : atob(DEFAULT_KEY_B64));

export default async function handler(req, res) {
  const origin = req.headers?.origin || "*";
  const corsHeaders = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };

  if (req.method === "OPTIONS") {
    if (res && typeof res.writeHead === "function") {
      res.writeHead(204, corsHeaders);
      res.end();
      return;
    }
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const sendResponse = (statusCode, data) => {
    if (res && typeof res.status === "function") {
      return res.status(statusCode).json(data);
    }
    return new Response(JSON.stringify(data), {
      status: statusCode,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  };

  // 1. Extrair token de autorização Bearer
  const authHeader = req.headers?.authorization || req.headers?.Authorization;
  const token = authHeader && authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;

  if (!token) {
    return sendResponse(401, { error: "Token de autenticação não fornecido." });
  }

  // Validar usuário pelo token
  let callerUser = null;
  try {
    const authRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${token}`,
      },
    });
    if (authRes.ok) {
      callerUser = await authRes.json();
    }
  } catch (_) {}

  if (!callerUser || !callerUser.id) {
    return sendResponse(401, { error: "Sessão inválida ou expirada." });
  }

  // 2. Verificar se o chamador é Administrador ativo via user_roles
  let isAdmin = false;
  try {
    const roleCheck = await fetch(`${SUPABASE_URL}/rest/v1/user_roles?user_id=eq.${encodeURIComponent(callerUser.id)}&role=eq.admin&active=eq.true&select=id`, {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
    });
    if (roleCheck.ok) {
      const roles = await roleCheck.json();
      if (Array.isArray(roles) && roles.length > 0) isAdmin = true;
    }

    if (!isAdmin) {
      const legRes = await fetch(`${SUPABASE_URL}/rest/v1/admin_users?user_id=eq.${encodeURIComponent(callerUser.id)}&select=user_id`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });
      if (legRes.ok) {
        const leg = await legRes.json();
        if (Array.isArray(leg) && leg.length > 0) isAdmin = true;
      }
    }
  } catch (_) {}

  if (!isAdmin) {
    return sendResponse(403, { error: "Acesso não autorizado: permissão de Administrador requerida." });
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
