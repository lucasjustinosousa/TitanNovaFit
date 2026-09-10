// Vercel Serverless Function: /api/subscriptions
// Gestão segura de planos, assinaturas e permissões do TitanNova Fit
// Integração: Atleta, Personal Trainer e Administrador (is_admin())

const SUPABASE_URL = process.env.SUPABASE_URL || "https://gplgywrvejefulsjpkax.supabase.co";
const DEFAULT_KEY_B64 = "c2Jfc2VjcmV0X2p5eWdfVC0tdDhPWFNPQ3k0NXB1blFfNXpwcG5vaGs=";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || (typeof Buffer !== "undefined" ? Buffer.from(DEFAULT_KEY_B64, "base64").toString("utf-8") : atob(DEFAULT_KEY_B64));

export default async function handler(req, res) {
  const origin = req.headers?.origin || "*";
  const corsHeaders = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
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

  // Helper para validar usuário pelo token Supabase
  const getAuthUser = async (userToken) => {
    if (!userToken) return null;
    try {
      const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${userToken}`,
        },
      });
      if (!response.ok) return null;
      return await response.json();
    } catch {
      return null;
    }
  };

  // Helper para verificar se usuário é Administrador exclusivamente via banco
  const verifyIsAdmin = async (userId) => {
    if (!userId) return false;
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/user_roles?user_id=eq.${encodeURIComponent(userId)}&role=eq.admin&active=eq.true&select=id`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });
      if (!response.ok) return false;
      const data = await response.json();
      if (Array.isArray(data) && data.length > 0) return true;

      // Fallback para admin_users legado
      const legacyResp = await fetch(`${SUPABASE_URL}/rest/v1/admin_users?user_id=eq.${encodeURIComponent(userId)}&select=user_id`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });
      if (legacyResp.ok) {
        const leg = await legacyResp.json();
        return Array.isArray(leg) && leg.length > 0;
      }
      return false;
    } catch {
      return false;
    }
  };

  // Registrar log de auditoria
  const logAudit = async (adminId, action, targetType, targetId, prevData, newData) => {
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/admin_audit_logs`, {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          admin_user_id: adminId,
          action,
          target_type: targetType,
          target_id: targetId,
          previous_data: prevData || null,
          new_data: newData || null
        })
      });
    } catch (_) {}
  };

  const user = await getAuthUser(token);
  if (!user || !user.id) {
    return sendResponse(401, { error: "Não autorizado. Token de sessão inválido ou expirado." });
  }

  const isAdmin = await verifyIsAdmin(user.id);

  // ==============================================================================
  // GET: Obter status de assinatura e permissões (PlanProvider)
  // ==============================================================================
  if (req.method === "GET") {
    // Se for Administrador: acesso total administrativo sem cobrança nem plano
    if (isAdmin) {
      return sendResponse(200, {
        isAdmin: true,
        accountType: "admin",
        roles: ["admin"],
        currentPlan: null,
        subscriptionStatus: "not_applicable",
        features: "administrative_access",
        limits: null,
        currentPeriodEnd: null
      });
    }

    try {
      // Chamar get_my_entitlements via RPC se disponível
      const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_my_entitlements`, {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({})
      });

      if (rpcRes.ok) {
        const entData = await rpcRes.json();
        if (entData && !entData.error) {
          return sendResponse(200, entData);
        }
      }

      // Fallback direto via banco
      const subRes = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${encodeURIComponent(user.id)}&status=in.(active,trialing)&select=id,plan_id,status,billing_cycle,current_period_end&order=created_at.desc&limit=1`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        }
      });

      let activeSub = { plan_id: "free", status: "active", billing_cycle: "free" };
      if (subRes.ok) {
        const subs = await subRes.json();
        if (Array.isArray(subs) && subs.length > 0) activeSub = subs[0];
      }

      const roleRes = await fetch(`${SUPABASE_URL}/rest/v1/user_roles?user_id=eq.${encodeURIComponent(user.id)}&active=eq.true&select=role`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        }
      });
      let role = "athlete";
      if (roleRes.ok) {
        const roles = await roleRes.json();
        if (Array.isArray(roles) && roles.length > 0) role = roles[0].role;
      }

      return sendResponse(200, {
        isAdmin: false,
        accountType: role,
        roles: [role],
        currentPlan: activeSub.plan_id || "free",
        subscriptionStatus: activeSub.status || "active",
        billingCycle: activeSub.billing_cycle || "free",
        features: {},
        limits: {},
        currentPeriodEnd: activeSub.current_period_end || null
      });
    } catch (err) {
      return sendResponse(500, { error: "Erro ao consultar permissões: " + err.message });
    }
  }

  // ==============================================================================
  // POST: Ações de escolha de plano, checkout e administração
  // ==============================================================================
  if (req.method === "POST") {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : (req.body || {});
    const action = body.action || req.query?.action;

    // 1. Escolha do Plano Grátis (Idempotente & Não Destrutivo)
    if (action === "choose_free") {
      try {
        const subCheck = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${encodeURIComponent(user.id)}&select=*`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });
        const currentSubs = await subCheck.json();
        const existingSub = Array.isArray(currentSubs) && currentSubs.length > 0 ? currentSubs[0] : null;

        if (existingSub && existingSub.plan_id !== "free" && existingSub.status === "active") {
          if (!body.confirm_downgrade) {
            return sendResponse(400, {
              requires_confirmation: true,
              message: "Você já possui um plano pago ativo. Ao retornar ao plano Grátis, seus treinos e históricos existentes serão preservados, mas novos treinos acima da cota gratuita serão bloqueados."
            });
          }
        }

        const upsertRes = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "resolution=merge-duplicates"
          },
          body: JSON.stringify({
            user_id: user.id,
            plan_id: "free",
            status: "active",
            billing_cycle: "free",
            provider: "manual",
            current_period_start: new Date().toISOString(),
            current_period_end: null,
            cancel_at_period_end: false,
            updated_at: new Date().toISOString()
          })
        });

        if (!upsertRes.ok) {
          throw new Error("Falha ao salvar assinatura gratuita no banco.");
        }

        return sendResponse(200, {
          success: true,
          plan: "free",
          message: "Plano Grátis ativado com sucesso! Bons treinos."
        });
      } catch (err) {
        return sendResponse(500, { error: err.message });
      }
    }

    // 2. Criação de Sessão de Pagamento para Planos Pagos
    if (action === "checkout_session") {
      const planCode = body.plan_code;
      if (!["bronze", "silver", "gold"].includes(planCode)) {
        return sendResponse(400, { error: "Plano pago inválido." });
      }

      // Enquanto o webhook do gateway não estiver integrado, aviso transparente
      return sendResponse(200, {
        status: "coming_soon",
        plan_code: planCode,
        message: "Assinaturas pagas em breve! Em ambiente de testes, solicite ao administrador a liberação temporária.",
        redirect_url: null
      });
    }

    // 3. ADMIN: Concessão Manual de Plano de Teste
    if (action === "admin_grant" || action === "admin-assign" || action === "admin_assign") {
      if (!isAdmin) {
        return sendResponse(403, { error: "Acesso restrito a administradores." });
      }

      const targetUserId = body.target_user_id || body.targetUserId;
      const targetPlanCode = body.target_plan_code || body.planCode || "gold";
      const durationDays = parseInt(body.duration_days || body.durationDays) || 30;

      if (!targetUserId) {
        return sendResponse(400, { error: "target_user_id obrigatório." });
      }

      try {
        const expiresAt = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000).toISOString();

        const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "resolution=merge-duplicates"
          },
          body: JSON.stringify({
            user_id: targetUserId,
            plan_id: targetPlanCode,
            status: "active",
            billing_cycle: "monthly",
            provider: "admin_grant",
            current_period_start: new Date().toISOString(),
            current_period_end: expiresAt,
            cancel_at_period_end: true,
            updated_at: new Date().toISOString()
          })
        });

        if (!updateRes.ok) throw new Error("Erro ao atualizar assinatura.");

        await logAudit(user.id, "plan_granted", "subscription", targetUserId, null, {
          plan: targetPlanCode,
          durationDays,
          expiresAt
        });

        return sendResponse(200, {
          success: true,
          message: `Plano ${targetPlanCode.toUpperCase()} concedido para testes com validade até ${new Date(expiresAt).toLocaleDateString("pt-BR")}.`,
          expires_at: expiresAt
        });
      } catch (err) {
        return sendResponse(500, { error: err.message });
      }
    }

    // 4. ADMIN: Cancelar Concessão / Rebaixar para Free
    if (action === "admin_cancel") {
      if (!isAdmin) {
        return sendResponse(403, { error: "Acesso restrito a administradores." });
      }

      const targetUserId = body.target_user_id;
      if (!targetUserId) {
        return sendResponse(400, { error: "target_user_id obrigatório." });
      }

      try {
        await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${encodeURIComponent(targetUserId)}`, {
          method: "PATCH",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            plan_id: "free",
            status: "active",
            provider: "manual",
            current_period_end: null,
            cancel_at_period_end: false,
            updated_at: new Date().toISOString()
          })
        });

        await logAudit(user.id, "plan_removed", "subscription", targetUserId, null, { plan: "free" });

        return sendResponse(200, {
          success: true,
          message: "Assinatura rebaixada para o plano Grátis com sucesso."
        });
      } catch (err) {
        return sendResponse(500, { error: err.message });
      }
    }

    return sendResponse(400, { error: "Ação não reconhecida." });
  }

  return sendResponse(405, { error: "Método não permitido." });
}
