-- ==============================================================================
-- TITANNOVA FIT - ESQUEMA DE PAPÉIS (USER_ROLES), PLANOS E ACESSO DO ADMINISTRADOR
-- Versão: 4.5.0
-- Suporta: Atleta ('athlete'), Personal ('trainer'), Administrador ('admin')
-- Planos: Grátis ('free'), Bronze ('bronze'), Prata ('silver'), Gold ('gold')
-- Princípio: RLS Estrito + Funções SECURITY DEFINER + Preservação Total de Dados
-- ==============================================================================

-- 1. TABELA DE PAPÉIS DO USUÁRIO (public.user_roles)
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('athlete', 'trainer', 'admin')),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES auth.users(id),
    UNIQUE(user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_active ON public.user_roles(role, active);

-- 2. TABELA DE LOGS DE AUDITORIA ADMINISTRATIVA (public.admin_audit_logs)
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL REFERENCES auth.users(id),
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id TEXT,
    previous_data JSONB,
    new_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created_at ON public.admin_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin_id ON public.admin_audit_logs(admin_user_id);

-- 3. TABELA DE PLANOS (public.plans) COM PRECIFICAÇÃO EM BRL
CREATE TABLE IF NOT EXISTS public.plans (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    monthly_price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    annual_price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    active BOOLEAN NOT NULL DEFAULT true,
    display_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Inserção / Atualização dos 4 Planos Oficiais
INSERT INTO public.plans (id, code, name, description, monthly_price, annual_price, active, display_order)
VALUES
    ('free', 'free', 'Grátis', 'Recursos essenciais para organizar sua rotina de treinos.', 0.00, 0.00, true, 1),
    ('bronze', 'bronze', 'Bronze', 'Mais liberdade com treinos e histórico completos sem anúncios.', 7.90, 69.90, true, 2),
    ('silver', 'silver', 'Prata', 'Evolução avançada com gráficos de sobrecarga, recordes e análise.', 14.90, 129.90, true, 3),
    ('gold', 'gold', 'Gold', 'Experiência máxima, gestão expandida para até 100 alunos e prioridade.', 24.90, 219.90, true, 4)
ON CONFLICT (id) DO UPDATE SET
    code = EXCLUDED.code,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    monthly_price = EXCLUDED.monthly_price,
    annual_price = EXCLUDED.annual_price,
    active = EXCLUDED.active,
    display_order = EXCLUDED.display_order,
    updated_at = now();

-- 4. TABELA DE RECURSOS E LIMITES POR PLANO (public.plan_features)
CREATE TABLE IF NOT EXISTS public.plan_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id TEXT NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
    feature_id TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT false,
    limit_value INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(plan_id, feature_id)
);

CREATE INDEX IF NOT EXISTS idx_plan_features_plan_id ON public.plan_features(plan_id);

-- 5. TABELA DE ASSINATURAS DOS USUÁRIOS (public.subscriptions)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL REFERENCES public.plans(id),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'trialing', 'past_due', 'canceled', 'expired', 'incomplete')),
    billing_cycle TEXT NOT NULL DEFAULT 'free' CHECK (billing_cycle IN ('free', 'monthly', 'annual')),
    provider TEXT DEFAULT 'manual',
    provider_subscription_id TEXT,
    current_period_start TIMESTAMPTZ DEFAULT now(),
    current_period_end TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);

-- ==============================================================================
-- 6. FUNÇÃO SEGURA DE VALIDAÇÃO DO ADMINISTRADOR (is_admin())
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
          AND role = 'admin'
          AND active = true
    );
END;
$$;

-- Função auxiliar para checar admin por UUID de usuário específico
CREATE OR REPLACE FUNCTION public.is_user_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = p_user_id
          AND role = 'admin'
          AND active = true
    );
END;
$$;

-- ==============================================================================
-- 7. FUNÇÃO SEGURA DE REGISTRO DE AUDITORIA (log_admin_action())
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.log_admin_action(
    p_action TEXT,
    p_target_type TEXT,
    p_target_id TEXT,
    p_previous_data JSONB DEFAULT NULL,
    p_new_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_admin_id UUID;
    v_log_id UUID;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso não autorizado: apenas administradores ativos podem registrar ações de auditoria.';
    END IF;

    INSERT INTO public.admin_audit_logs (
        admin_user_id,
        action,
        target_type,
        target_id,
        previous_data,
        new_data,
        created_at
    )
    VALUES (
        v_admin_id,
        p_action,
        p_target_type,
        p_target_id,
        p_previous_data,
        p_new_data,
        now()
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

-- ==============================================================================
-- 8. FUNÇÕES DE PERMISSÕES, ENTITLEMENTS E CONSULTA DE PLANOS
-- ==============================================================================

-- 8.1. get_my_plan(): Retorna o código do plano ativo ou 'admin' se for administrador
CREATE OR REPLACE FUNCTION public.get_my_plan()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_plan_id TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN 'free';
    END IF;

    -- Administrador não possui plano comum
    IF public.is_admin() THEN
        RETURN 'admin';
    END IF;

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = v_user_id
      AND s.status IN ('active', 'trialing')
    ORDER BY s.created_at DESC
    LIMIT 1;

    RETURN COALESCE(v_plan_id, 'free');
END;
$$;

-- 8.2. get_my_entitlements(): Retorna mapa de permissões respeitando perfil e papel
CREATE OR REPLACE FUNCTION public.get_my_entitlements()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_is_adm BOOLEAN;
    v_plan_id TEXT;
    v_features JSONB;
    v_limits JSONB;
    v_role TEXT;
    v_sub RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Usuário não autenticado');
    END IF;

    v_is_adm := public.is_admin();

    -- Se for Administrador: acesso total sem limites e sem assinatura fictícia
    IF v_is_adm THEN
        RETURN jsonb_build_object(
            'isAdmin', true,
            'accountType', 'admin',
            'roles', jsonb_build_array('admin'),
            'currentPlan', NULL,
            'subscriptionStatus', 'not_applicable',
            'features', 'administrative_access',
            'limits', NULL,
            'currentPeriodEnd', NULL
        );
    END IF;

    -- Papel do usuário
    SELECT role INTO v_role
    FROM public.user_roles
    WHERE user_id = v_user_id AND active = true
    ORDER BY created_at ASC
    LIMIT 1;

    v_role := COALESCE(v_role, 'athlete');

    -- Assinatura ativa do usuário
    SELECT s.id, s.plan_id, s.status, s.billing_cycle, s.current_period_end
    INTO v_sub
    FROM public.subscriptions s
    WHERE s.user_id = v_user_id AND s.status IN ('active', 'trialing')
    ORDER BY s.created_at DESC
    LIMIT 1;

    v_plan_id := COALESCE(v_sub.plan_id, 'free');

    -- Mapa de features habilitadas
    SELECT jsonb_object_agg(feature_id, enabled)
    INTO v_features
    FROM public.plan_features
    WHERE plan_id = v_plan_id;

    -- Mapa de limites numéricos
    SELECT jsonb_object_agg(feature_id, limit_value)
    INTO v_limits
    FROM public.plan_features
    WHERE plan_id = v_plan_id AND limit_value IS NOT NULL;

    RETURN jsonb_build_object(
        'isAdmin', false,
        'accountType', v_role,
        'roles', jsonb_build_array(v_role),
        'currentPlan', v_plan_id,
        'subscriptionStatus', COALESCE(v_sub.status, 'active'),
        'billingCycle', COALESCE(v_sub.billing_cycle, 'free'),
        'features', COALESCE(v_features, '{}'::JSONB),
        'limits', COALESCE(v_limits, '{}'::JSONB),
        'currentPeriodEnd', v_sub.current_period_end
    );
END;
$$;

-- 8.3. has_feature(p_feature_key): Valida se o usuário autenticado possui o recurso
CREATE OR REPLACE FUNCTION public.has_feature(p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_enabled BOOLEAN;
BEGIN
    -- Administrador possui todos os recursos
    IF public.is_admin() THEN
        RETURN true;
    END IF;

    v_plan_id := public.get_my_plan();

    SELECT pf.enabled INTO v_enabled
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_id = p_feature_key;

    RETURN COALESCE(v_enabled, false);
END;
$$;

-- 8.4. get_feature_limit(p_feature_key): Retorna limite numérico ou NULL (sem limite)
CREATE OR REPLACE FUNCTION public.get_feature_limit(p_feature_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_limit INTEGER;
BEGIN
    -- Para administrador, sempre retorna NULL representando 'sem limite'
    IF public.is_admin() THEN
        RETURN NULL;
    END IF;

    v_plan_id := public.get_my_plan();

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_id = p_feature_key;

    RETURN v_limit;
END;
$$;

-- 8.5. can_create_workout(): Valida limite de treinos
CREATE OR REPLACE FUNCTION public.can_create_workout(p_user_id UUID DEFAULT auth.uid())
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_limit INTEGER;
    v_current_count INTEGER;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Usuário não autenticado');
    END IF;

    -- Administrador cria sem limites
    IF public.is_user_admin(p_user_id) THEN
        RETURN jsonb_build_object('allowed', true, 'limit', NULL, 'current', 0);
    END IF;

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_id = 'workout_limit';

    -- Se limite for nulo, acesso ilimitado
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object('allowed', true, 'limit', NULL, 'current', 0);
    END IF;

    SELECT COUNT(*) INTO v_current_count
    FROM public.workouts
    WHERE user_id = p_user_id;

    IF v_current_count < v_limit THEN
        RETURN jsonb_build_object('allowed', true, 'limit', v_limit, 'current', v_current_count);
    ELSE
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', format('Limite de %s fichas atingido para o plano %s. Faça upgrade para fichas ilimitadas.', v_limit, v_plan_id),
            'limit', v_limit,
            'current', v_current_count,
            'plan_id', v_plan_id
        );
    END IF;
END;
$$;

-- 8.6. can_add_student(): Valida limite de alunos do personal
CREATE OR REPLACE FUNCTION public.can_add_student(p_trainer_id UUID DEFAULT auth.uid())
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_limit INTEGER;
    v_current_count INTEGER;
BEGIN
    IF p_trainer_id IS NULL THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Personal não autenticado');
    END IF;

    -- Administrador sem limites
    IF public.is_user_admin(p_trainer_id) THEN
        RETURN jsonb_build_object('allowed', true, 'limit', NULL, 'current', 0);
    END IF;

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_trainer_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_id = 'trainer_students_limit';

    IF v_limit IS NULL THEN
        IF v_plan_id = 'free' THEN v_limit := 2;
        ELSIF v_plan_id = 'bronze' THEN v_limit := 10;
        ELSIF v_plan_id = 'silver' THEN v_limit := 30;
        ELSIF v_plan_id = 'gold' THEN v_limit := 100;
        ELSE v_limit := 2;
        END IF;
    END IF;

    SELECT COUNT(*) INTO v_current_count
    FROM public.trainer_athletes
    WHERE trainer_id = p_trainer_id AND status = 'active';

    IF v_current_count < v_limit THEN
        RETURN jsonb_build_object('allowed', true, 'limit', v_limit, 'current', v_current_count);
    ELSE
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', format('Limite de %s alunos ativos atingido no plano %s. Faça upgrade para adicionar mais alunos.', v_limit, v_plan_id),
            'limit', v_limit,
            'current', v_current_count,
            'plan_id', v_plan_id
        );
    END IF;
END;
$$;

-- ==============================================================================
-- 9. OPERAÇÕES ADMINISTRATIVAS SEGURAS (RPCs COM AUDITORIA)
-- ==============================================================================

-- 9.1. admin_grant_test_plan: Concede plano temporário para testes
CREATE OR REPLACE FUNCTION public.admin_grant_test_plan(
    p_user_id UUID,
    p_plan_code TEXT,
    p_duration_days INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_prev RECORD;
    v_expires_at TIMESTAMPTZ;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso não autorizado.';
    END IF;

    IF p_plan_code NOT IN ('free', 'bronze', 'silver', 'gold') THEN
        RAISE EXCEPTION 'Código de plano inválido: %', p_plan_code;
    END IF;

    SELECT * INTO v_prev FROM public.subscriptions WHERE user_id = p_user_id;

    v_expires_at := now() + (p_duration_days || ' days')::INTERVAL;

    INSERT INTO public.subscriptions (
        user_id,
        plan_id,
        status,
        billing_cycle,
        provider,
        current_period_start,
        current_period_end,
        cancel_at_period_end,
        updated_at
    )
    VALUES (
        p_user_id,
        p_plan_code,
        'active',
        'monthly',
        'admin_grant',
        now(),
        v_expires_at,
        true,
        now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        plan_id = EXCLUDED.plan_id,
        status = 'active',
        provider = 'admin_grant',
        current_period_start = now(),
        current_period_end = v_expires_at,
        cancel_at_period_end = true,
        updated_at = now();

    -- Registrar log de auditoria
    PERFORM public.log_admin_action(
        'plan_granted',
        'subscription',
        p_user_id::TEXT,
        to_jsonb(v_prev),
        jsonb_build_object('plan_id', p_plan_code, 'provider', 'admin_grant', 'expires_at', v_expires_at)
    );

    RETURN jsonb_build_object('success', true, 'expires_at', v_expires_at, 'plan', p_plan_code);
END;
$$;

-- 9.2. admin_cancel_subscription: Cancela concessão ou rebaixa para free
CREATE OR REPLACE FUNCTION public.admin_cancel_subscription(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_prev RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso não autorizado.';
    END IF;

    SELECT * INTO v_prev FROM public.subscriptions WHERE user_id = p_user_id;

    UPDATE public.subscriptions
    SET plan_id = 'free',
        status = 'active',
        provider = 'manual',
        current_period_end = NULL,
        cancel_at_period_end = false,
        updated_at = now()
    WHERE user_id = p_user_id;

    PERFORM public.log_admin_action(
        'plan_removed',
        'subscription',
        p_user_id::TEXT,
        to_jsonb(v_prev),
        jsonb_build_object('plan_id', 'free', 'status', 'active')
    );

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 9.3. admin_suspend_user: Suspende ou reativa acesso de um usuário
CREATE OR REPLACE FUNCTION public.admin_suspend_user(p_user_id UUID, p_suspend BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso não autorizado.';
    END IF;

    -- Não suspender outros administradores
    IF public.is_user_admin(p_user_id) AND p_suspend THEN
        RAISE EXCEPTION 'Não é permitido suspender contas de administradores via painel.';
    END IF;

    UPDATE public.user_roles
    SET active = NOT p_suspend
    WHERE user_id = p_user_id;

    PERFORM public.log_admin_action(
        CASE WHEN p_suspend THEN 'user_suspended' ELSE 'user_reactivated' END,
        'user',
        p_user_id::TEXT,
        NULL,
        jsonb_build_object('suspended', p_suspend)
    );

    RETURN jsonb_build_object('success', true, 'suspended', p_suspend);
END;
$$;

-- 9.4. admin_verify_cref: Homologa ou recusa CREF de personal
CREATE OR REPLACE FUNCTION public.admin_verify_cref(
    p_trainer_user_id UUID,
    p_approved BOOLEAN,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso não autorizado.';
    END IF;

    v_status := CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END;

    UPDATE public.trainer_profiles
    SET verification_status = v_status,
        rejection_reason = p_rejection_reason,
        verified_at = CASE WHEN p_approved THEN now() ELSE NULL END,
        updated_at = now()
    WHERE user_id = p_trainer_user_id;

    PERFORM public.log_admin_action(
        CASE WHEN p_approved THEN 'cref_approved' ELSE 'cref_rejected' END,
        'trainer_profile',
        p_trainer_user_id::TEXT,
        NULL,
        jsonb_build_object('status', v_status, 'reason', p_rejection_reason)
    );

    RETURN jsonb_build_object('success', true, 'status', v_status);
END;
$$;

-- ==============================================================================
-- 10. POLÍTICAS DE SEGURANÇA ROW LEVEL SECURITY (RLS)
-- ==============================================================================

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- 10.1. user_roles: Usuário lê o próprio papel; Admin lê todos; Bloqueada escrita direta
DROP POLICY IF EXISTS "Usuário lê o próprio papel ou admin" ON public.user_roles;
CREATE POLICY "Usuário lê o próprio papel ou admin"
ON public.user_roles FOR SELECT
USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Bloquear escrita direta de user_roles pelo cliente" ON public.user_roles;
CREATE POLICY "Bloquear escrita direta de user_roles pelo cliente"
ON public.user_roles FOR ALL
USING (false)
WITH CHECK (false);

-- 10.2. admin_audit_logs: Apenas Admin pode ler; UPDATE/DELETE bloqueados para todos
DROP POLICY IF EXISTS "Admin visualiza logs de auditoria" ON public.admin_audit_logs;
CREATE POLICY "Admin visualiza logs de auditoria"
ON public.admin_audit_logs FOR SELECT
USING (public.is_admin());

DROP POLICY IF EXISTS "Bloquear escrita e exclusão direta de logs de auditoria" ON public.admin_audit_logs;
CREATE POLICY "Bloquear escrita e exclusão direta de logs de auditoria"
ON public.admin_audit_logs FOR ALL
USING (false)
WITH CHECK (false);

-- 10.3. subscriptions: Usuário lê apenas a sua; Admin lê todas; Escrita direta bloqueada
DROP POLICY IF EXISTS "Usuário consulta apenas sua própria assinatura ou admin" ON public.subscriptions;
CREATE POLICY "Usuário consulta apenas sua própria assinatura ou admin"
ON public.subscriptions FOR SELECT
USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Bloquear modificação direta de assinaturas pelo cliente" ON public.subscriptions;
CREATE POLICY "Bloquear modificação direta de assinaturas pelo cliente"
ON public.subscriptions FOR ALL
USING (false)
WITH CHECK (false);

-- ==============================================================================
-- 11. GATILHO DE ATRIBUIÇÃO AUTOMÁTICA E IDEMPOTENTE NO CADASTRO
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.handle_user_signup_roles_and_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_chosen_role TEXT;
BEGIN
    -- Capturar papel escolhido no cadastro (jamais permitir 'admin' por cadastro público)
    v_chosen_role := NEW.raw_user_meta_data->>'account_type';
    IF v_chosen_role NOT IN ('athlete', 'trainer') THEN
        v_chosen_role := 'athlete';
    END IF;

    -- 1. Registrar em user_roles
    INSERT INTO public.user_roles (user_id, role, active)
    VALUES (NEW.id, v_chosen_role, true)
    ON CONFLICT (user_id, role) DO NOTHING;

    -- 2. Criar assinatura inicial gratuita
    INSERT INTO public.subscriptions (
        user_id,
        plan_id,
        status,
        billing_cycle,
        provider,
        current_period_start
    )
    VALUES (
        NEW.id,
        'free',
        'active',
        'free',
        'manual',
        now()
    )
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_signup_roles ON auth.users;
CREATE TRIGGER on_auth_user_signup_roles
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_signup_roles_and_plan();

-- ==============================================================================
-- 12. BACKFILL NÃO DESTRUTIVO PARA CONTAS EXISTENTES
-- ==============================================================================
DO $$
BEGIN
    -- Migrar administradores já existentes
    INSERT INTO public.user_roles (user_id, role, active)
    SELECT au.user_id, 'admin', true
    FROM public.admin_users au
    ON CONFLICT (user_id, role) DO UPDATE SET active = true;

    -- Migrar personais já existentes
    INSERT INTO public.user_roles (user_id, role, active)
    SELECT p.id, 'trainer', true
    FROM public.profiles p
    WHERE p.account_type = 'trainer'
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Atribuir papel 'athlete' para os demais usuários
    INSERT INTO public.user_roles (user_id, role, active)
    SELECT u.id, 'athlete', true
    FROM auth.users u
    LEFT JOIN public.user_roles ur ON ur.user_id = u.id
    WHERE ur.id IS NULL
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Garantir assinatura no plano 'free' para todos que não possuem
    INSERT INTO public.subscriptions (user_id, plan_id, status, billing_cycle, provider, current_period_start)
    SELECT u.id, 'free', 'active', 'free', 'manual', now()
    FROM auth.users u
    LEFT JOIN public.subscriptions s ON s.user_id = u.id
    WHERE s.id IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = u.id AND ur.role = 'admin')
    ON CONFLICT (user_id) DO NOTHING;
END $$;
