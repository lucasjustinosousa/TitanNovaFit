-- ==============================================================================
-- TITANNOVA FIT - SISTEMA DE PLANOS E ASSINATURAS (SUPABASE MIGRATION)
-- Versão: 3.2.0
-- Planos: Grátis ('free'), Bronze ('bronze'), Prata ('silver'), Gold ('gold')
-- Arquitetura Segura: RLS Estrito + Funções SECURITY DEFINER + Preservação Total
-- ==============================================================================

-- 1. TABELA DE PLANOS (public.plans)
CREATE TABLE IF NOT EXISTS public.plans (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    monthly_price_cents INTEGER,
    yearly_price_cents INTEGER,
    currency TEXT NOT NULL DEFAULT 'BRL',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. INSERÇÃO IDEMPOTENTE DOS 4 PLANOS (Preços em breve)
INSERT INTO public.plans (id, name, description, display_order, is_active, monthly_price_cents, yearly_price_cents)
VALUES
    ('free', 'Grátis', 'Recursos essenciais para começar a organizar seus treinos.', 1, true, NULL, NULL),
    ('bronze', 'Bronze', 'Mais liberdade para montar e acompanhar sua rotina.', 2, true, NULL, NULL),
    ('silver', 'Prata', 'Acompanhamento avançado para entender sua evolução.', 3, true, NULL, NULL),
    ('gold', 'Gold', 'Todos os recursos e acesso antecipado às novidades.', 4, true, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    display_order = EXCLUDED.display_order,
    is_active = EXCLUDED.is_active,
    updated_at = now();

-- 3. TABELA DE RECURSOS E LIMITES POR PLANO (public.plan_features)
CREATE TABLE IF NOT EXISTS public.plan_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id TEXT NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
    feature_key TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT false,
    limit_value INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(plan_id, feature_key)
);

-- 4. TABELA DE ASSINATURAS DOS USUÁRIOS (public.subscriptions)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL REFERENCES public.plans(id),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'trialing', 'past_due', 'canceled', 'expired')),
    provider TEXT DEFAULT 'manual',
    provider_customer_id TEXT,
    provider_subscription_id TEXT,
    current_period_start TIMESTAMPTZ DEFAULT now(),
    current_period_end TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- Índices de consulta rápida
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_plan_id ON public.subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_features_plan_id ON public.plan_features(plan_id);

-- ==============================================================================
-- 5. CONFIGURAÇÃO DE RECURSOS (PLAN_FEATURES) PARA CADA PLANO
-- ==============================================================================

DO $$
BEGIN
    -- Limpar recursos existentes para recadastramento idempotente
    DELETE FROM public.plan_features WHERE plan_id IN ('free', 'bronze', 'silver', 'gold');

    -- ----------------------------------------------------
    -- PLANO GRÁTIS ('free')
    -- ----------------------------------------------------
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value) VALUES
        ('free', 'workout_limit', true, 3),              -- Até 3 fichas de treino
        ('free', 'unlimited_workouts', false, NULL),      -- Fichas ilimitadas: NÃO
        ('free', 'exercise_library', true, NULL),         -- Biblioteca de exercícios: SIM
        ('free', 'gif_demonstrations', true, NULL),       -- GIFs demonstrativos: SIM
        ('free', 'custom_exercises', true, NULL),         -- Exercícios personalizados: SIM
        ('free', 'sets_and_reps', true, NULL),            -- Registro de séries e cargas: SIM
        ('free', 'rest_timer', true, NULL),               -- Cronômetro de descanso: SIM
        ('free', 'advanced_timer', false, NULL),          -- Cronômetro avançado: NÃO
        ('free', 'history_days', true, 30),               -- Histórico: 30 dias
        ('free', 'full_history', false, NULL),            -- Histórico completo: NÃO
        ('free', 'beginner_templates', true, NULL),       -- Modelos: Iniciante
        ('free', 'all_level_templates', false, NULL),     -- Todos os modelos: NÃO
        ('free', 'workout_assistant', false, NULL),       -- Assistente de montagem básico (sem IA)
        ('free', 'advanced_charts', false, NULL),         -- Gráficos avançados: NÃO
        ('free', 'monthly_report', false, NULL),          -- Relatório mensal: NÃO
        ('free', 'supersets', false, NULL),               -- Superséries: NÃO
        ('free', 'plate_calculator', false, NULL),        -- Calculadora de anilhas: NÃO
        ('free', 'qr_sharing', false, NULL),              -- QR Code: NÃO
        ('free', 'coach_mode', false, NULL),              -- Professor e aluno: NÃO
        ('free', 'smartwatch_integration', false, NULL),  -- Relógios: NÃO
        ('free', 'offline_mode', true, NULL),             -- Offline básico: SIM
        ('free', 'data_export', true, NULL),              -- Exportação de dados: SIM
        ('free', 'account_deletion', true, NULL),         -- Exclusão de conta: SIM
        ('free', 'privacy_settings', true, NULL),         -- Privacidade: SIM
        ('free', 'remove_ads', false, NULL);              -- Sem publicidade: NÃO (poderá existir)

    -- ----------------------------------------------------
    -- PLANO BRONZE ('bronze')
    -- ----------------------------------------------------
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value) VALUES
        ('bronze', 'workout_limit', true, NULL),           -- Fichas ilimitadas
        ('bronze', 'unlimited_workouts', true, NULL),
        ('bronze', 'exercise_library', true, NULL),
        ('bronze', 'gif_demonstrations', true, NULL),
        ('bronze', 'custom_exercises', true, NULL),
        ('bronze', 'sets_and_reps', true, NULL),
        ('bronze', 'rest_timer', true, NULL),
        ('bronze', 'advanced_timer', true, NULL),          -- Cronômetro avançado
        ('bronze', 'history_days', true, NULL),            -- Histórico completo
        ('bronze', 'full_history', true, NULL),
        ('bronze', 'beginner_templates', true, NULL),
        ('bronze', 'intermediate_templates', true, NULL),  -- Modelos iniciante e intermediário
        ('bronze', 'all_level_templates', false, NULL),
        ('bronze', 'workout_assistant', true, NULL),       -- Assistente de montagem completo
        ('bronze', 'workout_duplication', true, NULL),     -- Duplicação de fichas
        ('bronze', 'advanced_library_filters', true, NULL),-- Filtros avançados
        ('bronze', 'advanced_charts', false, NULL),
        ('bronze', 'monthly_report', false, NULL),
        ('bronze', 'supersets', false, NULL),
        ('bronze', 'plate_calculator', false, NULL),
        ('bronze', 'qr_sharing', false, NULL),
        ('bronze', 'coach_mode', false, NULL),
        ('bronze', 'smartwatch_integration', false, NULL),
        ('bronze', 'offline_mode', true, NULL),            -- Offline completo
        ('bronze', 'data_export', true, NULL),             -- Exportação CSV e JSON
        ('bronze', 'account_deletion', true, NULL),
        ('bronze', 'privacy_settings', true, NULL),
        ('bronze', 'remove_ads', true, NULL);              -- Zero anúncios

    -- ----------------------------------------------------
    -- PLANO PRATA ('silver') - "Mais Escolhido"
    -- ----------------------------------------------------
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value) VALUES
        ('silver', 'workout_limit', true, NULL),
        ('silver', 'unlimited_workouts', true, NULL),
        ('silver', 'exercise_library', true, NULL),
        ('silver', 'gif_demonstrations', true, NULL),
        ('silver', 'custom_exercises', true, NULL),
        ('silver', 'sets_and_reps', true, NULL),
        ('silver', 'rest_timer', true, NULL),
        ('silver', 'advanced_timer', true, NULL),
        ('silver', 'history_days', true, NULL),
        ('silver', 'full_history', true, NULL),
        ('silver', 'beginner_templates', true, NULL),
        ('silver', 'intermediate_templates', true, NULL),
        ('silver', 'all_level_templates', true, NULL),     -- Todos os modelos
        ('silver', 'workout_assistant', true, NULL),
        ('silver', 'workout_duplication', true, NULL),
        ('silver', 'advanced_library_filters', true, NULL),
        ('silver', 'advanced_charts', true, NULL),         -- Gráficos avançados
        ('silver', 'personal_records', true, NULL),        -- Recordes pessoais (PRs)
        ('silver', 'workout_comparison', true, NULL),      -- Comparação com treino anterior
        ('silver', 'monthly_report', true, NULL),          -- Relatório mensal
        ('silver', 'supersets', true, NULL),               -- Superséries e drop sets
        ('silver', 'plate_calculator', true, NULL),        -- Calculadora de anilhas
        ('silver', 'progress_photos', true, NULL),         -- Fotos de progresso privadas
        ('silver', 'body_measurements', true, NULL),       -- Medidas corporais
        ('silver', 'rpe_tracking', true, NULL),            -- RPE opcional
        ('silver', 'qr_sharing', false, NULL),
        ('silver', 'coach_mode', false, NULL),
        ('silver', 'smartwatch_integration', false, NULL),
        ('silver', 'offline_mode', true, NULL),
        ('silver', 'data_export', true, NULL),
        ('silver', 'account_deletion', true, NULL),
        ('silver', 'privacy_settings', true, NULL),
        ('silver', 'remove_ads', true, NULL);

    -- ----------------------------------------------------
    -- PLANO GOLD ('gold') - "Experiência Completa"
    -- ----------------------------------------------------
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value) VALUES
        ('gold', 'workout_limit', true, NULL),
        ('gold', 'unlimited_workouts', true, NULL),
        ('gold', 'exercise_library', true, NULL),
        ('gold', 'gif_demonstrations', true, NULL),
        ('gold', 'custom_exercises', true, NULL),
        ('gold', 'sets_and_reps', true, NULL),
        ('gold', 'rest_timer', true, NULL),
        ('gold', 'advanced_timer', true, NULL),
        ('gold', 'history_days', true, NULL),
        ('gold', 'full_history', true, NULL),
        ('gold', 'beginner_templates', true, NULL),
        ('gold', 'intermediate_templates', true, NULL),
        ('gold', 'all_level_templates', true, NULL),
        ('gold', 'workout_assistant', true, NULL),
        ('gold', 'workout_duplication', true, NULL),
        ('gold', 'advanced_library_filters', true, NULL),
        ('gold', 'advanced_charts', true, NULL),
        ('gold', 'personal_records', true, NULL),
        ('gold', 'workout_comparison', true, NULL),
        ('gold', 'monthly_report', true, NULL),
        ('gold', 'supersets', true, NULL),
        ('gold', 'plate_calculator', true, NULL),
        ('gold', 'progress_photos', true, NULL),
        ('gold', 'body_measurements', true, NULL),
        ('gold', 'rpe_tracking', true, NULL),
        ('gold', 'workout_folders', true, NULL),           -- Pastas de treino
        ('gold', 'priority_support', true, NULL),          -- Suporte prioritário
        ('gold', 'qr_sharing', false, NULL),               -- Em desenvolvimento (não liberado antes do lançamento)
        ('gold', 'coach_mode', false, NULL),               -- Disponível em breve (não liberado antes do lançamento)
        ('gold', 'smartwatch_integration', false, NULL),   -- Disponível em breve (não liberado antes do lançamento)
        ('gold', 'offline_mode', true, NULL),
        ('gold', 'data_export', true, NULL),
        ('gold', 'account_deletion', true, NULL),
        ('gold', 'privacy_settings', true, NULL),
        ('gold', 'remove_ads', true, NULL);
END $$;

-- ==============================================================================
-- 6. SEGURANÇA E ROW LEVEL SECURITY (RLS)
-- ==============================================================================

ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- 6.1. Policies para public.plans
DROP POLICY IF EXISTS "Permitir leitura pública de planos ativos" ON public.plans;
CREATE POLICY "Permitir leitura pública de planos ativos" 
ON public.plans FOR SELECT 
USING (is_active = true);

DROP POLICY IF EXISTS "Bloquear escrita pública de planos" ON public.plans;
CREATE POLICY "Bloquear escrita pública de planos" 
ON public.plans FOR ALL 
USING (false)
WITH CHECK (false);

-- 6.2. Policies para public.plan_features
DROP POLICY IF EXISTS "Permitir leitura pública de recursos dos planos" ON public.plan_features;
CREATE POLICY "Permitir leitura pública de recursos dos planos" 
ON public.plan_features FOR SELECT 
USING (true);

DROP POLICY IF EXISTS "Bloquear escrita pública de recursos" ON public.plan_features;
CREATE POLICY "Bloquear escrita pública de recursos" 
ON public.plan_features FOR ALL 
USING (false)
WITH CHECK (false);

-- 6.3. Policies para public.subscriptions
DROP POLICY IF EXISTS "Usuário consulta apenas sua própria assinatura ou admin" ON public.subscriptions;
CREATE POLICY "Usuário consulta apenas sua própria assinatura ou admin" 
ON public.subscriptions FOR SELECT 
USING (
    auth.uid() = user_id 
    OR EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid())
);

-- Usuários NUNCA podem inserir, editar ou deletar assinaturas diretamente do frontend
DROP POLICY IF EXISTS "Bloquear inserção direta de assinaturas pelo cliente" ON public.subscriptions;
CREATE POLICY "Bloquear inserção direta de assinaturas pelo cliente" 
ON public.subscriptions FOR INSERT 
WITH CHECK (false);

DROP POLICY IF EXISTS "Bloquear alteração direta de assinaturas pelo cliente" ON public.subscriptions;
CREATE POLICY "Bloquear alteração direta de assinaturas pelo cliente" 
ON public.subscriptions FOR UPDATE 
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "Bloquear exclusão direta de assinaturas pelo cliente" ON public.subscriptions;
CREATE POLICY "Bloquear exclusão direta de assinaturas pelo cliente" 
ON public.subscriptions FOR DELETE 
USING (false);

-- ==============================================================================
-- 7. FUNÇÕES SEGURAS (SECURITY DEFINER)
-- ==============================================================================

-- 7.1. Retornar dados completos e verificados da assinatura do usuário atual
CREATE OR REPLACE FUNCTION public.get_my_subscription()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_sub RECORD;
    v_features JSONB;
    v_limits JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Usuário não autenticado');
    END IF;

    -- Se for administrador oficial, retornar acesso administrativo irrestrito
    IF EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = v_user_id)
       OR EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_user_id AND role = 'admin' AND active = true)
       OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id AND (account_type = 'admin' OR role = 'admin')) THEN
        RETURN jsonb_build_object(
            'is_admin', true,
            'plan_code', 'admin',
            'plan_name', 'Administrador (Acesso Total)',
            'status', 'active',
            'features', 'administrative_access',
            'limits', null
        );
    END IF;

    -- Localizar assinatura ativa do usuário
    SELECT 
        s.id AS subscription_id,
        s.status,
        s.provider,
        s.current_period_start,
        s.current_period_end,
        p.id AS plan_id,
        p.name AS plan_name,
        p.description AS plan_description
    INTO v_sub
    FROM public.subscriptions s
    JOIN public.plans p ON p.id = s.plan_id
    WHERE s.user_id = v_user_id
      AND s.status IN ('active', 'trialing')
    ORDER BY s.created_at DESC
    LIMIT 1;

    -- Se não encontrar assinatura ativa, busca o plano Grátis como padrão
    IF v_sub IS NULL THEN
        SELECT 
            NULL::UUID AS subscription_id,
            'active' AS status,
            'manual' AS provider,
            now() AS current_period_start,
            NULL::TIMESTAMPTZ AS current_period_end,
            p.id AS plan_id,
            p.name AS plan_name,
            p.description AS plan_description
        INTO v_sub
        FROM public.plans p
        WHERE p.id = 'free'
        LIMIT 1;
    END IF;

    -- Carregar mapa de features habilitadas
    SELECT jsonb_object_agg(feature_key, enabled)
    INTO v_features
    FROM public.plan_features
    WHERE plan_id = v_sub.plan_id;

    -- Carregar mapa de limites
    SELECT jsonb_object_agg(feature_key, limit_value)
    INTO v_limits
    FROM public.plan_features
    WHERE plan_id = v_sub.plan_id AND limit_value IS NOT NULL;

    RETURN jsonb_build_object(
        'subscription_id', v_sub.subscription_id,
        'plan_id', v_sub.plan_id,
        'plan_code', v_sub.plan_id,
        'plan_name', v_sub.plan_name,
        'status', v_sub.status,
        'provider', v_sub.provider,
        'current_period_start', v_sub.current_period_start,
        'current_period_end', v_sub.current_period_end,
        'features', COALESCE(v_features, '{}'::JSONB),
        'limits', COALESCE(v_limits, '{}'::JSONB)
    );
END;
$$;

-- 7.2. Validar se o usuário pode criar uma nova ficha de treino
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

    -- Descobrir plano ativo
    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    -- Buscar limite de fichas para o plano
    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = 'workout_limit';

    -- Se limite for nulo, acesso irrestrito
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object('allowed', true, 'limit', NULL);
    END IF;

    -- Contar fichas existentes do usuário
    SELECT COUNT(*) INTO v_current_count
    FROM public.workouts
    WHERE user_id = p_user_id;

    IF v_current_count >= v_limit THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'current_count', v_current_count,
            'limit', v_limit,
            'reason', 'Limite de fichas do plano Grátis atingido. Faça upgrade para fichas ilimitadas.'
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'current_count', v_current_count,
        'limit', v_limit
    );
END;
$$;

-- 7.3. Checar permissão de uma funcionalidade específica
CREATE OR REPLACE FUNCTION public.can_use_feature(p_user_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_enabled BOOLEAN;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN false;
    END IF;

    -- Administrador possui acesso irrestrito
    IF EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = p_user_id)
       OR EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = p_user_id AND role = 'admin' AND active = true)
       OR EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND (account_type = 'admin' OR role = 'admin')) THEN
        RETURN true;
    END IF;

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.enabled INTO v_enabled
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = p_feature_key;

    RETURN COALESCE(v_enabled, false);
END;
$$;

-- 7.4. Retornar limite numérico de uma funcionalidade
CREATE OR REPLACE FUNCTION public.get_feature_limit(p_user_id UUID, p_feature_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_plan_id TEXT;
    v_limit INTEGER;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Administrador não é submetido a limites numéricos
    IF EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = p_user_id)
       OR EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = p_user_id AND role = 'admin' AND active = true)
       OR EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND (account_type = 'admin' OR role = 'admin')) THEN
        RETURN NULL;
    END IF;

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = p_feature_key;

    RETURN v_limit;
END;
$$;

-- ==============================================================================
-- 8. GATILHO SEGURO DE ATRIBUIÇÃO AUTOMÁTICA PARA NOVOS USUÁRIOS
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    INSERT INTO public.subscriptions (
        user_id,
        plan_id,
        status,
        provider,
        current_period_start
    )
    VALUES (
        NEW.id,
        'free',
        'active',
        'manual',
        now()
    )
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_subscription ON auth.users;
CREATE TRIGGER on_auth_user_created_subscription
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user_subscription();

-- ==============================================================================
-- 9. MIGRAÇÃO SEGURA (BACKFILL) PARA USUÁRIOS EXISTENTES
-- ==============================================================================

DO $$
BEGIN
    -- Associa o plano Grátis a todos os usuários existentes que não possuem registro
    INSERT INTO public.subscriptions (user_id, plan_id, status, provider, current_period_start)
    SELECT u.id, 'free', 'active', 'manual', now()
    FROM auth.users u
    LEFT JOIN public.subscriptions s ON s.user_id = u.id
    WHERE s.id IS NULL
    ON CONFLICT (user_id) DO NOTHING;
END $$;
