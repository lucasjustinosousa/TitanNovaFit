import { getSupabaseServerConfig, createCorsHeaders } from "./_config.js";

export default async function handler(req, res) {
  const origin = req.headers?.origin || "*";
  const corsHeaders = createCorsHeaders(origin, "GET, POST, OPTIONS");

  if (res && typeof res.setHeader === "function") {
    Object.entries(corsHeaders).forEach(([key, val]) => res.setHeader(key, val));
  }

  if (req.method === "OPTIONS") {
    if (res && typeof res.status === "function") {
      return res.status(200).end();
    }
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const sendResponse = (status, data) => {
    if (res && typeof res.status === "function") {
      return res.status(status).json(data);
    }
    return new Response(JSON.stringify(data), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  };

  const config = getSupabaseServerConfig();
  if (!config.isValid) {
    return sendResponse(500, { error: config.error });
  }
  const { supabaseUrl: SUPABASE_URL, serviceRoleKey: SERVICE_ROLE_KEY } = config;

  const authHeader = req.headers?.authorization || "";
  const token = authHeader.replace("Bearer ", "").trim();

  // Helper para obter usuário autenticado pelo token JWT do Supabase
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

  // Helper para verificar se usuário é Administrador
  const verifyIsAdmin = async (userId) => {
    if (!userId) return false;
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/admin_users?user_id=eq.${encodeURIComponent(userId)}&select=user_id`, {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });
      if (!response.ok) return false;
      const data = await response.json();
      return Array.isArray(data) && data.length > 0;
    } catch {
      return false;
    }
  };

  const action = (req.query && req.query.action) || (req.body && req.body.action);

  // ==============================================================================
  // AÇÃO PÚBLICA / SEM LOGIN OBRIGATÓRIO: CONSULTAR DETALHES DO CONVITE
  // ==============================================================================
  if (action === "invite-details") {
    const inviteToken = req.query?.token || (req.body && req.body.token);
    if (!inviteToken) {
      return sendResponse(400, { valid: false, error: "Token de convite não fornecido." });
    }

    try {
      const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_invite_details`, {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ p_token: inviteToken })
      });

      if (!rpcRes.ok) {
        return sendResponse(400, { valid: false, error: "Falha ao consultar convite." });
      }

      const inviteData = await rpcRes.json();
      return sendResponse(200, inviteData);
    } catch (err) {
      return sendResponse(500, { valid: false, error: "Erro interno ao processar convite." });
    }
  }

  // A partir daqui, autenticação é estritamente obrigatória
  const user = await getAuthUser(token);
  if (!user || !user.id) {
    return sendResponse(401, { error: "Não autorizado. Faça login para acessar esta funcionalidade." });
  }

  // ==============================================================================
  // GET: LISTAR ALUNOS (PARA PERSONAL) OU PERSONAL (PARA ATLETA)
  // ==============================================================================
  if (req.method === "GET") {
    if (action === "my-students") {
      try {
        // Consultar alunos vinculados na tabela trainer_athletes
        const relRes = await fetch(`${SUPABASE_URL}/rest/v1/trainer_athletes?trainer_id=eq.${encodeURIComponent(user.id)}&select=id,athlete_id,status,invited_at,accepted_at&order=created_at.desc`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });

        if (!relRes.ok) {
          return sendResponse(500, { error: "Erro ao consultar alunos vinculados." });
        }

        const relationships = await relRes.json();
        const studentIds = relationships.map(r => r.athlete_id);

        let profilesMap = {};
        if (studentIds.length > 0) {
          const profRes = await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=in.(${studentIds.map(encodeURIComponent).join(",")})&select=id,name,email,avatar_url,goal,experience_level`, {
            headers: {
              apikey: SERVICE_ROLE_KEY,
              Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            }
          });
          if (profRes.ok) {
            const profiles = await profRes.json();
            profiles.forEach(p => { profilesMap[p.id] = p; });
          }
        }

        // Consultar atribuições de treino ativas
        const assignmentsRes = await fetch(`${SUPABASE_URL}/rest/v1/workout_assignments?trainer_id=eq.${encodeURIComponent(user.id)}&select=id,athlete_id,workout_id,status,starts_at,ends_at`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });
        const assignments = assignmentsRes.ok ? await assignmentsRes.json() : [];

        // Consultar limite do personal
        const limitRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_trainer_student_limit`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ p_trainer_id: user.id })
        });
        const studentLimit = limitRes.ok ? await limitRes.json() : 2;

        const students = relationships.map(rel => {
          const prof = profilesMap[rel.athlete_id] || {};
          const studentAssignments = assignments.filter(a => a.athlete_id === rel.athlete_id);
          return {
            relationship_id: rel.id,
            athlete_id: rel.athlete_id,
            name: prof.name || "Atleta",
            email: prof.email || "",
            avatar_url: prof.avatar_url,
            goal: prof.goal || "Geral",
            experience_level: prof.experience_level || "Iniciante",
            status: rel.status,
            accepted_at: rel.accepted_at,
            assigned_workouts_count: studentAssignments.length,
            last_workout_date: null
          };
        });

        const activeCount = students.filter(s => s.status === "active").length;

        return sendResponse(200, {
          students,
          limit: studentLimit,
          active_count: activeCount,
          limit_reached: activeCount >= studentLimit
        });
      } catch (err) {
        return sendResponse(500, { error: "Erro ao buscar alunos do personal." });
      }
    }

    if (action === "my-trainer") {
      try {
        // Consultar vínculo ativo do atleta
        const relRes = await fetch(`${SUPABASE_URL}/rest/v1/trainer_athletes?athlete_id=eq.${encodeURIComponent(user.id)}&status=eq.active&select=id,trainer_id,accepted_at&limit=1`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });

        if (!relRes.ok) return sendResponse(500, { error: "Erro ao consultar personal." });
        const relList = await relRes.json();
        if (!Array.isArray(relList) || relList.length === 0) {
          return sendResponse(200, { has_trainer: false, trainer: null, assignments: [] });
        }

        const activeRel = relList[0];

        // Consultar perfil profissional do personal
        const profRes = await fetch(`${SUPABASE_URL}/rest/v1/trainer_profiles?user_id=eq.${encodeURIComponent(activeRel.trainer_id)}&select=professional_name,biography,cref_number,cref_state,verification_status,city,state,specialties`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });
        const trainerProfiles = profRes.ok ? await profRes.json() : [];
        const trainerProfile = (trainerProfiles && trainerProfiles[0]) || {};

        // Consultar treinos atribuídos
        const assignRes = await fetch(`${SUPABASE_URL}/rest/v1/workout_assignments?athlete_id=eq.${encodeURIComponent(user.id)}&trainer_id=eq.${encodeURIComponent(activeRel.trainer_id)}&select=id,workout_id,workout_data,status,starts_at,ends_at,trainer_notes,assigned_at&order=assigned_at.desc`, {
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          }
        });
        const assignments = assignRes.ok ? await assignRes.json() : [];

        return sendResponse(200, {
          has_trainer: true,
          relationship_id: activeRel.id,
          trainer: {
            id: activeRel.trainer_id,
            professional_name: trainerProfile.professional_name || "Personal Trainer",
            biography: trainerProfile.biography,
            cref_number: trainerProfile.cref_number,
            cref_state: trainerProfile.cref_state,
            verification_status: trainerProfile.verification_status || "not_submitted",
            city: trainerProfile.city,
            state: trainerProfile.state,
            specialties: trainerProfile.specialties || [],
            linked_since: activeRel.accepted_at
          },
          assignments
        });
      } catch (err) {
        return sendResponse(500, { error: "Erro ao buscar dados do personal vinculado." });
      }
    }
  }

  // ==============================================================================
  // POST: AÇÕES DE NEGÓCIO DO PERSONAL / ATLETA / ADMIN
  // ==============================================================================
  if (req.method === "POST") {
    let body = {};
    try {
      body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
    } catch {
      body = {};
    }

    // 1. CRIAR CONVITE DE ALUNO
    if (action === "create-invite") {
      const athleteEmail = body.athleteEmail || null;
      const expiresDays = parseInt(body.expiresDays, 10) || 7;

      try {
        const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/create_trainer_invite`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            p_athlete_email: athleteEmail,
            p_expires_days: expiresDays
          })
        });

        if (!rpcRes.ok) {
          const errText = await rpcRes.text();
          return sendResponse(400, { error: `Erro ao criar convite: ${errText}` });
        }

        const result = await rpcRes.json();
        if (!result.success) {
          return sendResponse(400, { error: result.error });
        }

        const inviteToken = result.invite_token;
        const appOrigin = req.headers?.origin || "https://titannovafit.com.br";
        const inviteLink = `${appOrigin}/app?invite=${encodeURIComponent(inviteToken)}`;

        const whatsappMessage = `Olá! Preparei um treino para você no TitanNova Fit. Acesse o link para entrar na sua conta e visualizar a ficha: ${inviteLink}`;

        return sendResponse(200, {
          success: true,
          invite_token: inviteToken,
          invite_link: inviteLink,
          whatsapp_message: whatsappMessage,
          expires_at: result.expires_at
        });
      } catch (err) {
        return sendResponse(500, { error: "Falha ao gerar convite." });
      }
    }

    // 2. ACEITAR CONVITE
    if (action === "accept-invite") {
      const inviteToken = body.inviteToken;
      if (!inviteToken) return sendResponse(400, { error: "Token de convite obrigatório." });

      try {
        const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/accept_trainer_invite`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ p_token: inviteToken })
        });

        const result = await rpcRes.json();
        if (!result.success) {
          return sendResponse(400, { error: result.error || "Não foi possível aceitar o convite." });
        }

        return sendResponse(200, result);
      } catch (err) {
        return sendResponse(500, { error: "Erro ao aceitar convite." });
      }
    }

    // 3. RECUSAR CONVITE
    if (action === "reject-invite") {
      const inviteToken = body.inviteToken;
      if (!inviteToken) return sendResponse(400, { error: "Token de convite obrigatório." });

      try {
        await fetch(`${SUPABASE_URL}/rest/v1/rpc/reject_trainer_invite`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ p_token: inviteToken })
        });
        return sendResponse(200, { success: true });
      } catch (err) {
        return sendResponse(500, { error: "Erro ao recusar convite." });
      }
    }

    // 4. ATRIBUIR TREINO AO ALUNO
    if (action === "assign-workout") {
      const athleteId = body.athleteId;
      const workoutId = body.workoutId;
      const workoutData = body.workoutData;
      const notes = body.trainerNotes || "";
      const startsAt = body.startsAt || new Date().toISOString();
      const endsAt = body.endsAt || null;

      if (!athleteId || !workoutId || !workoutData) {
        return sendResponse(400, { error: "Dados incompletos para atribuição de treino." });
      }

      try {
        const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/assign_workout_to_athlete`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            p_athlete_id: athleteId,
            p_workout_id: String(workoutId),
            p_workout_data: workoutData,
            p_trainer_notes: notes,
            p_starts_at: startsAt,
            p_ends_at: endsAt
          })
        });

        const result = await rpcRes.json();
        if (!result.success) {
          return sendResponse(400, { error: result.error || "Não foi possível atribuir o treino." });
        }

        return sendResponse(200, result);
      } catch (err) {
        return sendResponse(500, { error: "Erro ao salvar atribuição de treino." });
      }
    }

    // 5. ENCERRAR VÍNCULO (PELO ALUNO OU PELO PERSONAL)
    if (action === "remove-relationship") {
      const targetUserId = body.targetUserId;
      if (!targetUserId) return sendResponse(400, { error: "ID do usuário alvo obrigatório." });

      try {
        const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/remove_trainer_athlete_relationship`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ p_target_user_id: targetUserId })
        });

        const result = await rpcRes.json();
        return sendResponse(200, result);
      } catch (err) {
        return sendResponse(500, { error: "Erro ao encerrar vínculo." });
      }
    }

    // 6. VERIFICAÇÃO ADMINISTRATIVA DE CREF
    if (action === "admin-verify-cref") {
      const isAdmin = await verifyIsAdmin(user.id);
      if (!isAdmin) {
        return sendResponse(403, { error: "Apenas administradores podem verificar cadastros de CREF." });
      }

      const trainerId = body.trainerId;
      const newStatus = body.newStatus; // 'approved' ou 'rejected'
      const notes = body.notes || "";

      if (!trainerId || !newStatus) {
        return sendResponse(400, { error: "ID do personal e status são obrigatórios." });
      }

      try {
        const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/admin_verify_cref`, {
          method: "POST",
          headers: {
            apikey: SERVICE_ROLE_KEY,
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            p_trainer_id: trainerId,
            p_new_status: newStatus,
            p_notes: notes
          })
        });

        const result = await rpcRes.json();
        return sendResponse(200, result);
      } catch (err) {
        return sendResponse(500, { error: "Erro ao atualizar verificação de CREF." });
      }
    }
  }

  return sendResponse(400, { error: "Ação não suportada ou método inválido." });
}
