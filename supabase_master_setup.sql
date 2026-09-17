-- ==============================================================================
-- TITANNOVA FIT - SCRIPT MESTRE CONSOLIDADO E IDEMPOTENTE
-- Arquivo: supabase_master_setup.sql
-- Objetivo: Criar todas as tabelas pendentes, tipos, índices, RLS estrito e
--           funções SECURITY DEFINER sem causar conflitos nem perda de dados.
-- Compatibilidade: Supabase PostgreSQL 15+
-- ==============================================================================

-- 1. EXTENSÕES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TABELA DE PERFIS (public.profiles)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT 'Atleta TitanNova',
    nome TEXT NOT NULL DEFAULT 'Atleta TitanNova',
    email TEXT NOT NULL DEFAULT '',
    avatar_url TEXT,
    account_type TEXT NOT NULL DEFAULT 'athlete' CHECK (account_type IN ('athlete', 'trainer', 'admin')),
    role TEXT NOT NULL DEFAULT 'athlete',
    phone TEXT,
    birth_date DATE,
    goal TEXT,
    experience_level TEXT,
    active BOOLEAN NOT NULL DEFAULT true,
    local_migration_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Garantir colunas essenciais caso profiles já exista
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='nome') THEN
        ALTER TABLE public.profiles ADD COLUMN nome TEXT NOT NULL DEFAULT 'Atleta TitanNova';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='role') THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT NOT NULL DEFAULT 'athlete';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='local_migration_completed_at') THEN
        ALTER TABLE public.profiles ADD COLUMN local_migration_completed_at TIMESTAMPTZ;
    END IF;
END $$;

-- 3. TABELA DE PAPÉIS DE USUÁRIO (public.user_roles)
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('athlete', 'trainer', 'admin')),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, role)
);
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON public.user_roles(user_id);

-- 4. TABELA DE PERFIL DE PERSONAL TRAINER (public.trainer_profiles)
CREATE TABLE IF NOT EXISTS public.trainer_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    professional_name TEXT NOT NULL DEFAULT '',
    biography TEXT,
    cref_number TEXT,
    cref_state TEXT,
    verification_status TEXT NOT NULL DEFAULT 'not_submitted' CHECK (verification_status IN ('not_submitted', 'pending', 'approved', 'rejected')),
    specialties TEXT[] DEFAULT '{}',
    city TEXT,
    state TEXT,
    maximum_students INTEGER DEFAULT 2,
    admin_verification_notes TEXT,
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_trainer_profile_user UNIQUE (user_id)
);
CREATE INDEX IF NOT EXISTS idx_trainer_profiles_user ON public.trainer_profiles(user_id);

-- 5. TABELA DE RELACIONAMENTO PERSONAL & ATLETA (public.trainer_athletes)
CREATE TABLE IF NOT EXISTS public.trainer_athletes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    athlete_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'active', 'rejected', 'removed', 'blocked')),
    invited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at TIMESTAMPTZ,
    removed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_trainer_athlete UNIQUE (trainer_id, athlete_id)
);
CREATE INDEX IF NOT EXISTS idx_trainer_athletes_trainer ON public.trainer_athletes(trainer_id);
CREATE INDEX IF NOT EXISTS idx_trainer_athletes_athlete ON public.trainer_athletes(athlete_id);

-- 6. TABELA DE CONVITES DE PERSONAL (public.trainer_invites)
CREATE TABLE IF NOT EXISTS public.trainer_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    athlete_email TEXT,
    token_hash TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'canceled')),
    expires_at TIMESTAMPTZ NOT NULL,
    maximum_uses INTEGER NOT NULL DEFAULT 1,
    used_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_trainer_invites_trainer ON public.trainer_invites(trainer_id);
CREATE INDEX IF NOT EXISTS idx_trainer_invites_token ON public.trainer_invites(token_hash);

-- 7. TABELA DE PRESCRIÇÃO / ATRIBUIÇÃO DE TREINOS (public.workout_assignments)
CREATE TABLE IF NOT EXISTS public.workout_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    athlete_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_id TEXT NOT NULL,
    workout_title TEXT NOT NULL,
    workout_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    notes_from_trainer TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_workout_assignments_athlete ON public.workout_assignments(athlete_id);
CREATE INDEX IF NOT EXISTS idx_workout_assignments_trainer ON public.workout_assignments(trainer_id);

-- 8. TABELA DE COMENTÁRIOS DE ATRIBUIÇÃO (public.workout_assignment_comments)
CREATE TABLE IF NOT EXISTS public.workout_assignment_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.workout_assignments(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    comment TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assignment_comments ON public.workout_assignment_comments(assignment_id);

-- 9. TABELA DE ACEITE DE TERMOS E LGPD (public.legal_acceptances)
CREATE TABLE IF NOT EXISTS public.legal_acceptances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    terms_version TEXT NOT NULL DEFAULT '1.0',
    privacy_version TEXT NOT NULL DEFAULT '1.0',
    birth_date DATE,
    parental_consent BOOLEAN NOT NULL DEFAULT false,
    parental_name TEXT,
    parental_document TEXT,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_address TEXT,
    user_agent TEXT,
    UNIQUE(user_id, terms_version, privacy_version)
);
CREATE INDEX IF NOT EXISTS idx_legal_acceptances_user ON public.legal_acceptances(user_id);

-- 10. TABELA DE EXERCÍCIOS FAVORITOS (public.exercicios_favoritos)
CREATE TABLE IF NOT EXISTS public.exercicios_favoritos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercicio_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, exercicio_id)
);
CREATE INDEX IF NOT EXISTS idx_exercicios_favoritos_user ON public.exercicios_favoritos(user_id);

-- ==============================================================================
-- 11. FUNÇÕES SEGURAS (SECURITY DEFINER) COM SEARCH_PATH BLINDADO
-- ==============================================================================

-- 11.1. Função autoritativa is_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_uid UUID;
    v_is_adm BOOLEAN := false;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN false;
    END IF;

    -- Checagem em user_roles
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = v_uid AND role = 'admin' AND active = true
    ) INTO v_is_adm;

    IF v_is_adm THEN
        RETURN true;
    END IF;

    -- Checagem em admin_users
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'admin_users') THEN
        SELECT EXISTS (
            SELECT 1 FROM public.admin_users 
            WHERE user_id = v_uid
        ) INTO v_is_adm;

        IF v_is_adm THEN
            RETURN true;
        END IF;
    END IF;

    -- Checagem em profiles
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = v_uid AND (account_type = 'admin' OR role = 'admin') AND active = true
    ) INTO v_is_adm;

    IF v_is_adm THEN
        RETURN true;
    END IF;

    -- Checagem em metadata
    SELECT COALESCE(
        (u.raw_app_meta_data->>'is_admin')::BOOLEAN,
        (u.raw_user_meta_data->>'is_admin')::BOOLEAN,
        false
    ) INTO v_is_adm
    FROM auth.users u
    WHERE u.id = v_uid;

    RETURN COALESCE(v_is_adm, false);
END;
$$;

-- 11.2. Função autoritativa get_my_entitlements()
CREATE OR REPLACE FUNCTION public.get_my_entitlements()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_uid UUID;
    v_is_adm BOOLEAN;
    v_account_type TEXT := 'athlete';
    v_roles TEXT[] := ARRAY['athlete'];
    v_sub RECORD;
    v_features JSONB := '{}'::JSONB;
    v_limits JSONB := '{"workout_limit": 3, "history_days": 30}'::JSONB;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('error', 'Usuário não autenticado');
    END IF;

    v_is_adm := public.is_admin();

    IF v_is_adm THEN
        RETURN jsonb_build_object(
            'is_admin', true,
            'account_type', 'admin',
            'roles', jsonb_build_array('admin'),
            'plan_code', 'admin',
            'plan_name', 'Administrador (Acesso Total)',
            'status', 'active',
            'features', 'administrative_access',
            'limits', null
        );
    END IF;

    -- Obter tipo de conta do perfil
    SELECT COALESCE(account_type, 'athlete') INTO v_account_type
    FROM public.profiles
    WHERE id = v_uid;

    v_account_type := COALESCE(v_account_type, 'athlete');
    v_roles := ARRAY[v_account_type];

    -- Obter assinatura ativa
    SELECT s.plan_id, p.name AS plan_name, s.status, s.current_period_end
    INTO v_sub
    FROM public.subscriptions s
    JOIN public.plans p ON (p.id::text = s.plan_id::text OR p.code = s.plan_id::text)
    WHERE s.user_id = v_uid AND s.status IN ('active', 'trialing')
    LIMIT 1;

    RETURN jsonb_build_object(
        'is_admin', false,
        'account_type', v_account_type,
        'roles', to_jsonb(v_roles),
        'plan_code', COALESCE(v_sub.plan_id::text, 'free'),
        'plan_name', COALESCE(v_sub.plan_name, 'Grátis'),
        'status', COALESCE(v_sub.status, 'active'),
        'current_period_end', v_sub.current_period_end,
        'features', v_features,
        'limits', v_limits
    );
END;
$$;

-- 11.3. Função get_all_users() com validação estrita de admin
CREATE OR REPLACE FUNCTION public.get_all_users()
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    created_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    is_admin BOOLEAN,
    account_type TEXT,
    plan_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado: permissão de Administrador requerida.';
    END IF;

    RETURN QUERY
    SELECT 
        u.id AS user_id,
        u.email::TEXT AS email,
        u.created_at AS created_at,
        u.last_sign_in_at AS last_sign_in_at,
        EXISTS (SELECT 1 FROM public.admin_users au WHERE au.user_id = u.id) AS is_admin,
        COALESCE(p.account_type, 'athlete')::TEXT AS account_type,
        COALESCE(s.plan_id::text, 'free')::TEXT AS plan_code
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    LEFT JOIN public.subscriptions s ON s.user_id = u.id AND s.status = 'active';
END;
$$;

-- 11.4. Função create_trainer_invite() com bloqueio de CREF pendente
CREATE OR REPLACE FUNCTION public.create_trainer_invite(
    p_athlete_email TEXT DEFAULT NULL,
    p_expires_days INTEGER DEFAULT 7,
    p_max_uses INTEGER DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_trainer_id UUID;
    v_cref_status TEXT;
    v_token TEXT;
    v_invite_id UUID;
BEGIN
    v_trainer_id := auth.uid();
    IF v_trainer_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Não autenticado.');
    END IF;

    -- Validar status do CREF (apenas aprovados ou admins podem convidar)
    IF NOT public.is_admin() THEN
        SELECT verification_status INTO v_cref_status
        FROM public.trainer_profiles
        WHERE user_id = v_trainer_id;

        IF v_cref_status IS NULL OR v_cref_status != 'approved' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Seu cadastro profissional está em análise. Convites serão liberados após homologação do CREF.'
            );
        END IF;
    END IF;

    v_token := encode(gen_random_bytes(24), 'hex');

    INSERT INTO public.trainer_invites (
        trainer_id,
        athlete_email,
        token_hash,
        status,
        expires_at,
        maximum_uses,
        used_count
    ) VALUES (
        v_trainer_id,
        p_athlete_email,
        v_token,
        'pending',
        now() + (p_expires_days || ' days')::INTERVAL,
        COALESCE(p_max_uses, 1),
        0
    ) RETURNING id INTO v_invite_id;

    RETURN jsonb_build_object(
        'success', true,
        'invite_id', v_invite_id,
        'token', v_token
    );
END;
$$;

-- ==============================================================================
-- 12. ROW LEVEL SECURITY (RLS) E POLÍTICAS ESTRITAS
-- ==============================================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_athletes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_assignment_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercicios_favoritos ENABLE ROW LEVEL SECURITY;

-- 12.1. Policies para profiles
DROP POLICY IF EXISTS "Usuário lê seu próprio perfil" ON public.profiles;
CREATE POLICY "Usuário lê seu próprio perfil" ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "Usuário altera seu próprio perfil" ON public.profiles;
CREATE POLICY "Usuário altera seu próprio perfil" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Usuário insere seu próprio perfil" ON public.profiles;
CREATE POLICY "Usuário insere seu próprio perfil" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- 12.2. Policies para trainer_profiles
DROP POLICY IF EXISTS "Leitura de perfil de personal" ON public.trainer_profiles;
CREATE POLICY "Leitura de perfil de personal" ON public.trainer_profiles FOR SELECT USING (auth.uid() = user_id OR verification_status = 'approved' OR public.is_admin());

DROP POLICY IF EXISTS "Personal altera seu próprio perfil" ON public.trainer_profiles;
CREATE POLICY "Personal altera seu próprio perfil" ON public.trainer_profiles FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Personal insere seu perfil" ON public.trainer_profiles;
CREATE POLICY "Personal insere seu perfil" ON public.trainer_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 12.3. Policies para trainer_athletes
DROP POLICY IF EXISTS "Participantes leem seus relacionamentos" ON public.trainer_athletes;
CREATE POLICY "Participantes leem seus relacionamentos" ON public.trainer_athletes FOR SELECT USING (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin());

-- 12.4. Policies para legal_acceptances
DROP POLICY IF EXISTS "Usuário lê seus aceites legais" ON public.legal_acceptances;
CREATE POLICY "Usuário lê seus aceites legais" ON public.legal_acceptances FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Usuário registra seu aceite legal" ON public.legal_acceptances;
CREATE POLICY "Usuário registra seu aceite legal" ON public.legal_acceptances FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 12.5. Policies para exercicios_favoritos
DROP POLICY IF EXISTS "Usuário gerencia seus favoritos" ON public.exercicios_favoritos;
CREATE POLICY "Usuário gerencia seus favoritos" ON public.exercicios_favoritos FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ==============================================================================
-- 13. PRIVILÉGIOS DE EXECUÇÃO EM FUNÇÕES
-- ==============================================================================
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_entitlements() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_entitlements() TO authenticated;

REVOKE ALL ON FUNCTION public.get_all_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_users() TO authenticated;

REVOKE ALL ON FUNCTION public.create_trainer_invite(TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_trainer_invite(TEXT, INTEGER, INTEGER) TO authenticated;

-- ==============================================================================
-- FIM DA MIGRAÇÃO MESTRE CONSOLIDADA
-- ==============================================================================
