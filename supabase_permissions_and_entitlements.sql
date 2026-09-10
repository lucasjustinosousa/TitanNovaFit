-- ==============================================================================
-- TITANNOVA FIT - SISTEMA DE PERMISSÕES, ENTITLEMENTS E SEGURANÇA (RLS)
-- Versão: 4.0.0
-- Suporta: Atleta ('athlete'), Personal ('trainer'), Admin ('admin')
-- Planos: Grátis ('free'), Bronze ('bronze'), Prata ('silver'), Gold ('gold')
-- ==============================================================================

-- 1. GARANTIR COLUNAS EM WORKOUT_ASSIGNMENTS
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_assignments' AND column_name='workout_version') THEN
        ALTER TABLE public.workout_assignments ADD COLUMN workout_version INTEGER NOT NULL DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_assignments' AND column_name='trainer_notes') THEN
        ALTER TABLE public.workout_assignments ADD COLUMN trainer_notes TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_assignments' AND column_name='athlete_notes') THEN
        ALTER TABLE public.workout_assignments ADD COLUMN athlete_notes TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_assignments' AND column_name='assigned_at') THEN
        ALTER TABLE public.workout_assignments ADD COLUMN assigned_at TIMESTAMPTZ NOT NULL DEFAULT now();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workout_assignments' AND column_name='accepted_at') THEN
        ALTER TABLE public.workout_assignments ADD COLUMN accepted_at TIMESTAMPTZ;
    END IF;
END $$;

-- 2. GARANTIR COLUNAS EM TRAINER_ATHLETES
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trainer_athletes' AND column_name='invited_at') THEN
        ALTER TABLE public.trainer_athletes ADD COLUMN invited_at TIMESTAMPTZ NOT NULL DEFAULT now();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trainer_athletes' AND column_name='accepted_at') THEN
        ALTER TABLE public.trainer_athletes ADD COLUMN accepted_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trainer_athletes' AND column_name='removed_at') THEN
        ALTER TABLE public.trainer_athletes ADD COLUMN removed_at TIMESTAMPTZ;
    END IF;
END $$;

-- 3. GARANTIR COLUNAS EM TRAINER_INVITES
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trainer_invites' AND column_name='maximum_uses') THEN
        ALTER TABLE public.trainer_invites ADD COLUMN maximum_uses INTEGER NOT NULL DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='trainer_invites' AND column_name='used_count') THEN
        ALTER TABLE public.trainer_invites ADD COLUMN used_count INTEGER NOT NULL DEFAULT 0;
    END IF;
END $$;

-- 4. ATUALIZAR FEATURES DOS PLANOS PARA ATLETAS E PERSONAIS
DO $$
BEGIN
    -- Configuração de recursos específicos para Personal Trainers
    -- PLANO GRÁTIS PERSONAL: Até 2 alunos, até 5 modelos
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value)
    VALUES 
        ('free', 'trainer_students_limit', true, 2),
        ('free', 'trainer_templates_limit', true, 5),
        ('free', 'whatsapp_sharing', true, NULL),
        ('free', 'basic_assignment', true, NULL)
    ON CONFLICT (plan_id, feature_key) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        limit_value = EXCLUDED.limit_value;

    -- PLANO BRONZE PERSONAL: Até 10 alunos, modelos ilimitados
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value)
    VALUES 
        ('bronze', 'trainer_students_limit', true, 10),
        ('bronze', 'trainer_templates_limit', true, NULL),
        ('bronze', 'whatsapp_sharing', true, NULL),
        ('bronze', 'student_history', true, NULL),
        ('bronze', 'custom_exercises', true, NULL)
    ON CONFLICT (plan_id, feature_key) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        limit_value = EXCLUDED.limit_value;

    -- PLANO PRATA PERSONAL: Até 30 alunos, gráficos por aluno, relatórios
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value)
    VALUES 
        ('silver', 'trainer_students_limit', true, 30),
        ('silver', 'trainer_templates_limit', true, NULL),
        ('silver', 'student_charts', true, NULL),
        ('silver', 'student_reports', true, NULL),
        ('silver', 'multi_student_assignment', true, NULL),
        ('silver', 'professional_library', true, NULL)
    ON CONFLICT (plan_id, feature_key) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        limit_value = EXCLUDED.limit_value;

    -- PLANO GOLD PERSONAL: Até 100 alunos, painel profissional completo
    INSERT INTO public.plan_features (plan_id, feature_key, enabled, limit_value)
    VALUES 
        ('gold', 'trainer_students_limit', true, 100),
        ('gold', 'trainer_templates_limit', true, NULL),
        ('gold', 'batch_assignment', true, NULL),
        ('gold', 'advanced_reports', true, NULL),
        ('gold', 'professional_branding', true, NULL),
        ('gold', 'priority_support', true, NULL)
    ON CONFLICT (plan_id, feature_key) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        limit_value = EXCLUDED.limit_value;
END $$;

-- ==============================================================================
-- 5. FUNÇÕES SEGURAS (SECURITY DEFINER) EXIGIDAS
-- ==============================================================================

-- 5.1. get_my_plan(): Retorna o código do plano ativo ('free', 'bronze', 'silver', 'gold')
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

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = v_user_id
      AND s.status IN ('active', 'trialing')
    ORDER BY s.created_at DESC
    LIMIT 1;

    RETURN COALESCE(v_plan_id, 'free');
END;
$$;

-- 5.2. get_my_entitlements(): Retorna o mapa completo de permissões e limites do usuário
CREATE OR REPLACE FUNCTION public.get_my_entitlements()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_plan_id TEXT;
    v_features JSONB;
    v_limits JSONB;
    v_role TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Usuário não autenticado');
    END IF;

    -- Papel
    SELECT account_type INTO v_role
    FROM public.profiles
    WHERE id = v_user_id;

    v_role := COALESCE(v_role, 'athlete');

    -- Plano ativo
    v_plan_id := public.get_my_plan();

    -- Features
    SELECT jsonb_object_agg(feature_key, enabled)
    INTO v_features
    FROM public.plan_features
    WHERE plan_id = v_plan_id;

    -- Limites
    SELECT jsonb_object_agg(feature_key, limit_value)
    INTO v_limits
    FROM public.plan_features
    WHERE plan_id = v_plan_id AND limit_value IS NOT NULL;

    RETURN jsonb_build_object(
        'user_id', v_user_id,
        'role', v_role,
        'plan_id', v_plan_id,
        'features', COALESCE(v_features, '{}'::JSONB),
        'limits', COALESCE(v_limits, '{}'::JSONB)
    );
END;
$$;

-- 5.3. has_feature(p_feature_key): Valida se o usuário autenticado possui o recurso habilitado
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
    v_plan_id := public.get_my_plan();

    SELECT pf.enabled INTO v_enabled
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = p_feature_key;

    RETURN COALESCE(v_enabled, false);
END;
$$;

-- 5.4. get_feature_limit(p_feature_key): Retorna o valor numérico do limite (ou NULL para ilimitado)
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
    v_plan_id := public.get_my_plan();

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = p_feature_key;

    RETURN v_limit;
END;
$$;

-- 5.5. can_create_workout(): Valida limite de fichas de treino
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

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = 'workout_limit';

    -- Se limite for nulo, acesso irrestrito
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
            'reason', format('Limite de %s fichas atingido para o plano %s. Faça upgrade para o Bronze ou Prata para criar treinos ilimitados.', v_limit, v_plan_id),
            'limit', v_limit,
            'current', v_current_count,
            'plan_id', v_plan_id
        );
    END IF;
END;
$$;

-- 5.6. can_add_student(): Valida limite de alunos do Personal Trainer
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

    SELECT s.plan_id INTO v_plan_id
    FROM public.subscriptions s
    WHERE s.user_id = p_trainer_id AND s.status IN ('active', 'trialing')
    LIMIT 1;

    v_plan_id := COALESCE(v_plan_id, 'free');

    SELECT pf.limit_value INTO v_limit
    FROM public.plan_features pf
    WHERE pf.plan_id = v_plan_id AND pf.feature_key = 'trainer_students_limit';

    -- Padrão por plano caso não conste na tabela:
    -- free: 2, bronze: 10, silver: 30, gold: 100
    IF v_limit IS NULL THEN
        IF v_plan_id = 'free' THEN v_limit := 2;
        ELSIF v_plan_id = 'bronze' THEN v_limit := 10;
        ELSIF v_plan_id = 'silver' THEN v_limit := 30;
        ELSIF v_plan_id = 'gold' THEN v_limit := 100;
        ELSE v_limit := 2;
        END IF;
    END IF;

    -- Contar alunos ativos
    SELECT COUNT(*) INTO v_current_count
    FROM public.trainer_athletes
    WHERE trainer_id = p_trainer_id AND status = 'active';

    IF v_current_count < v_limit THEN
        RETURN jsonb_build_object('allowed', true, 'limit', v_limit, 'current', v_current_count);
    ELSE
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', format('Limite de %s alunos ativos atingido no seu plano atual (%s). Faça upgrade para adicionar mais alunos.', v_limit, v_plan_id),
            'limit', v_limit,
            'current', v_current_count,
            'plan_id', v_plan_id
        );
    END IF;
END;
$$;

-- 5.7. can_assign_workout(): Valida se personal pode atribuir treino a aluno
CREATE OR REPLACE FUNCTION public.can_assign_workout(p_trainer_id UUID DEFAULT auth.uid(), p_athlete_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_is_linked BOOLEAN;
BEGIN
    IF p_trainer_id IS NULL THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Personal não autenticado');
    END IF;

    IF p_athlete_id IS NOT NULL THEN
        -- Verificar se aluno possui vínculo ativo
        SELECT EXISTS (
            SELECT 1 FROM public.trainer_athletes 
            WHERE trainer_id = p_trainer_id AND athlete_id = p_athlete_id AND status = 'active'
        ) INTO v_is_linked;

        IF NOT v_is_linked THEN
            RETURN jsonb_build_object('allowed', false, 'reason', 'Aluno não possui vínculo ativo com este Personal Trainer.');
        END IF;
    END IF;

    RETURN jsonb_build_object('allowed', true);
END;
$$;

-- 6. REFORÇO DE POLÍTICAS DE RLS ESTREITAS
ALTER TABLE public.trainer_athletes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_assignment_comments ENABLE ROW LEVEL SECURITY;

-- 6.1. trainer_athletes RLS
DROP POLICY IF EXISTS "Personal e Atleta visualizam seus próprios relacionamentos" ON public.trainer_athletes;
CREATE POLICY "Personal e Atleta visualizam seus próprios relacionamentos"
ON public.trainer_athletes FOR SELECT
USING (auth.uid() = trainer_id OR auth.uid() = athlete_id);

-- 6.2. workout_assignments RLS
DROP POLICY IF EXISTS "Personal e Atleta visualizam fichas atribuídas mútuas" ON public.workout_assignments;
CREATE POLICY "Personal e Atleta visualizam fichas atribuídas mútuas"
ON public.workout_assignments FOR SELECT
USING (auth.uid() = trainer_id OR auth.uid() = athlete_id);

DROP POLICY IF EXISTS "Personal cria ou edita fichas atribuídas" ON public.workout_assignments;
CREATE POLICY "Personal cria ou edita fichas atribuídas"
ON public.workout_assignments FOR ALL
USING (auth.uid() = trainer_id)
WITH CHECK (auth.uid() = trainer_id);

-- 6.3. workout_assignment_comments RLS
DROP POLICY IF EXISTS "Personal e Atleta leem comentários da ficha" ON public.workout_assignment_comments;
CREATE POLICY "Personal e Atleta leem comentários da ficha"
ON public.workout_assignment_comments FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.workout_assignments wa 
        WHERE wa.id = assignment_id AND (wa.trainer_id = auth.uid() OR wa.athlete_id = auth.uid())
    )
);

DROP POLICY IF EXISTS "Personal e Atleta inserem comentários na ficha" ON public.workout_assignment_comments;
CREATE POLICY "Personal e Atleta inserem comentários na ficha"
ON public.workout_assignment_comments FOR INSERT
WITH CHECK (
    auth.uid() = author_id AND
    EXISTS (
        SELECT 1 FROM public.workout_assignments wa 
        WHERE wa.id = assignment_id AND (wa.trainer_id = auth.uid() OR wa.athlete_id = auth.uid())
    )
);
