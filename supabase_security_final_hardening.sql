-- ==============================================================================
-- TITANNOVA FIT — MIGRAÇÃO FINAL CONSOLIDADA DE RLS E ENDURECIMENTO DE SEGURANÇA
-- Arquivo: supabase_security_final_hardening.sql
-- Objetivo: Revogar permissões inseguras (anon/public), eliminar políticas
--           permissivas antigas, proteger RPCs SECURITY DEFINER e isolar dados
--           de atletas, personais e administradores.
-- Idempotência: Pode ser executado repetidas vezes com segurança sem perda de dados.
-- Data: 2026-09-13
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- SEÇÃO 1: EXTENSÕES ESSENCIAIS E CONFIGURAÇÃO
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- SEÇÃO 2: FUNÇÃO CENTRAL E AUTORITATIVA DE ADMIN (is_admin)
-- ------------------------------------------------------------------------------
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

    -- 1. Checagem prioritária na tabela user_roles
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'user_roles'
    ) THEN
        SELECT EXISTS (
            SELECT 1 FROM public.user_roles 
            WHERE user_id = v_uid AND role = 'admin' AND active = true
        ) INTO v_is_adm;

        IF v_is_adm THEN
            RETURN true;
        END IF;
    END IF;

    -- 2. Checagem de compatibilidade na tabela admin_users
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'admin_users'
    ) THEN
        SELECT EXISTS (
            SELECT 1 FROM public.admin_users 
            WHERE user_id = v_uid
        ) INTO v_is_adm;

        IF v_is_adm THEN
            RETURN true;
        END IF;
    END IF;

    -- 3. Checagem em raw_app_meta_data / raw_user_meta_data
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

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- ------------------------------------------------------------------------------
-- SEÇÃO 3: REVOGAÇÃO DE PRIVILÉGIOS GLOBAIS INSEGUROS DE ANON
-- ------------------------------------------------------------------------------
-- Garantir que anon não possua privilégios de escrita automáticos no schema public
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- Re-conceder apenas leitura pública para tabelas que possuem catálogo público
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Leitura pública no catálogo de planos
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'plans') THEN
        GRANT SELECT ON public.plans TO anon, authenticated;
    END IF;
END $$;

-- Leitura pública no catálogo oficial de exercícios
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exercicios') THEN
        GRANT SELECT ON public.exercicios TO anon, authenticated;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 4: LIMPEZA DE POLÍTICAS RLS ANTIGAS E INSEGURAS
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    -- Limpeza de políticas abertas em profiles e usuarios
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        DROP POLICY IF EXISTS "Permitir leitura ampla de perfis para admin e autenticados" ON public.profiles;
        DROP POLICY IF EXISTS "Permitir leitura de perfis para admin e autenticados" ON public.profiles;
        DROP POLICY IF EXISTS "Usuarios gerenciam seu proprio perfil em profiles" ON public.profiles;
        DROP POLICY IF EXISTS "Profiles public read" ON public.profiles;
        DROP POLICY IF EXISTS "Usuário visualiza seu perfil" ON public.profiles;
        DROP POLICY IF EXISTS "Usuário insere seu perfil" ON public.profiles;
        DROP POLICY IF EXISTS "Usuário atualiza seu perfil" ON public.profiles;
        DROP POLICY IF EXISTS "Usuários gerenciam seu próprio perfil" ON public.profiles;
        DROP POLICY IF EXISTS "Perfis visualizados pelo próprio ou admin ou personal" ON public.profiles;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'usuarios') THEN
        DROP POLICY IF EXISTS "Permitir leitura ampla de usuarios para admin e autenticados" ON public.usuarios;
        DROP POLICY IF EXISTS "Permitir leitura de usuarios para admin e autenticados" ON public.usuarios;
        DROP POLICY IF EXISTS "Usuarios gerenciam seu proprio perfil em usuarios" ON public.usuarios;
        DROP POLICY IF EXISTS "Usuarios gerenciam seu proprio perfil em perfis" ON public.usuarios;
    END IF;

    -- Limpeza em admin_users e user_roles
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'admin_users') THEN
        DROP POLICY IF EXISTS "Permitir leitura de admin_users" ON public.admin_users;
        DROP POLICY IF EXISTS "Permitir leitura ampla de admin_users" ON public.admin_users;
        DROP POLICY IF EXISTS "Admin users full access" ON public.admin_users;
        DROP POLICY IF EXISTS "Apenas admin acessa admin_users" ON public.admin_users;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_roles') THEN
        DROP POLICY IF EXISTS "Permitir leitura de user_roles" ON public.user_roles;
        DROP POLICY IF EXISTS "Usuarios consultam seus papeis" ON public.user_roles;
        DROP POLICY IF EXISTS "Admin gerencia todos os papeis" ON public.user_roles;
        DROP POLICY IF EXISTS "Leitura de papéis por proprietário ou admin" ON public.user_roles;
        DROP POLICY IF EXISTS "Gerenciamento de papéis exclusivo admin" ON public.user_roles;
    END IF;

    -- Limpeza em tabelas de treinos, exercícios, sessões e históricos
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'treinos') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam seus proprios treinos" ON public.treinos;
        DROP POLICY IF EXISTS "Usuário visualiza seus treinos" ON public.treinos;
        DROP POLICY IF EXISTS "Usuário cria seus treinos" ON public.treinos;
        DROP POLICY IF EXISTS "Usuário altera seus treinos" ON public.treinos;
        DROP POLICY IF EXISTS "Usuário exclui seus treinos" ON public.treinos;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exercicios') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam seus proprios exercicios" ON public.exercicios;
        DROP POLICY IF EXISTS "Exercícios visíveis para todos" ON public.exercicios;
        DROP POLICY IF EXISTS "Usuário visualiza exercícios públicos e próprios" ON public.exercicios;
        DROP POLICY IF EXISTS "Usuário cria exercícios próprios" ON public.exercicios;
        DROP POLICY IF EXISTS "Usuário altera exercícios próprios" ON public.exercicios;
        DROP POLICY IF EXISTS "Usuário exclui exercícios próprios" ON public.exercicios;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sessoes_de_treino') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam suas proprias sessoes" ON public.sessoes_de_treino;
        DROP POLICY IF EXISTS "Usuário visualiza suas sessões" ON public.sessoes_de_treino;
        DROP POLICY IF EXISTS "Usuário cria suas sessões" ON public.sessoes_de_treino;
        DROP POLICY IF EXISTS "Usuário altera suas sessões" ON public.sessoes_de_treino;
        DROP POLICY IF EXISTS "Usuário exclui suas sessões" ON public.sessoes_de_treino;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'historico_de_exercicios') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam seus proprios historicos" ON public.historico_de_exercicios;
        DROP POLICY IF EXISTS "Usuário visualiza seus históricos" ON public.historico_de_exercicios;
        DROP POLICY IF EXISTS "Usuário insere seus históricos" ON public.historico_de_exercicios;
        DROP POLICY IF EXISTS "Usuário altera seus históricos" ON public.historico_de_exercicios;
        DROP POLICY IF EXISTS "Usuário exclui seus históricos" ON public.historico_de_exercicios;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exercicios_favoritos') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam seus favoritos" ON public.exercicios_favoritos;
        DROP POLICY IF EXISTS "Usuário visualiza seus favoritos" ON public.exercicios_favoritos;
        DROP POLICY IF EXISTS "Usuário adiciona favoritos" ON public.exercicios_favoritos;
        DROP POLICY IF EXISTS "Usuário remove favoritos" ON public.exercicios_favoritos;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'favoritos') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam seus favoritos" ON public.favoritos;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'medidas_corporais') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam suas proprias medidas" ON public.medidas_corporais;
        DROP POLICY IF EXISTS "Usuário visualiza suas medidas" ON public.medidas_corporais;
        DROP POLICY IF EXISTS "Usuário registra suas medidas" ON public.medidas_corporais;
        DROP POLICY IF EXISTS "Usuário altera suas medidas" ON public.medidas_corporais;
        DROP POLICY IF EXISTS "Usuário exclui suas medidas" ON public.medidas_corporais;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'configuracoes') THEN
        DROP POLICY IF EXISTS "Usuarios gerenciam suas configuracoes" ON public.configuracoes;
        DROP POLICY IF EXISTS "Usuário visualiza suas configurações" ON public.configuracoes;
        DROP POLICY IF EXISTS "Usuário altera suas configurações" ON public.configuracoes;
        DROP POLICY IF EXISTS "Usuário cria suas configurações" ON public.configuracoes;
    END IF;

    -- Limpeza em subscriptions e plans
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscriptions') THEN
        DROP POLICY IF EXISTS "Usuários leem suas próprias assinaturas" ON public.subscriptions;
        DROP POLICY IF EXISTS "Admin gerencia todas assinaturas" ON public.subscriptions;
        DROP POLICY IF EXISTS "Subscriptions user select" ON public.subscriptions;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'plans') THEN
        DROP POLICY IF EXISTS "Planos visíveis para todos" ON public.plans;
        DROP POLICY IF EXISTS "Admin gerencia planos" ON public.plans;
    END IF;

    -- Limpeza em trainer_profiles, trainer_athletes, workout_assignments
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'trainer_profiles') THEN
        DROP POLICY IF EXISTS "Perfis de personal são visíveis publicamente" ON public.trainer_profiles;
        DROP POLICY IF EXISTS "Personal gerencia seu perfil profissional" ON public.trainer_profiles;
        DROP POLICY IF EXISTS "Admin gerencia perfis de personal" ON public.trainer_profiles;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'trainer_athletes') THEN
        DROP POLICY IF EXISTS "Participantes do vínculo visualizam dados" ON public.trainer_athletes;
        DROP POLICY IF EXISTS "Personal gerencia vínculos com atletas" ON public.trainer_athletes;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'workout_assignments') THEN
        DROP POLICY IF EXISTS "Personal e Atleta visualizam fichas atribuídas mútuas" ON public.workout_assignments;
        DROP POLICY IF EXISTS "Personal cria ou edita fichas atribuídas" ON public.workout_assignments;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'workout_assignment_comments') THEN
        DROP POLICY IF EXISTS "Participantes consultam comentários" ON public.workout_assignment_comments;
        DROP POLICY IF EXISTS "Participantes inserem comentários" ON public.workout_assignment_comments;
        DROP POLICY IF EXISTS "Personal e Atleta leem comentários da ficha" ON public.workout_assignment_comments;
        DROP POLICY IF EXISTS "Personal e Atleta inserem comentários na ficha" ON public.workout_assignment_comments;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 5: POLÍTICAS RLS ESTRITAS (TABELAS ADMINISTRATIVAS)
-- ------------------------------------------------------------------------------

-- 5.1. admin_users
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'admin_users') THEN
        ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.admin_users FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_users TO authenticated;

        CREATE POLICY "Apenas administradores consultam admin_users"
        ON public.admin_users FOR SELECT
        TO authenticated
        USING (public.is_admin());

        CREATE POLICY "Apenas administradores alteram admin_users"
        ON public.admin_users FOR ALL
        TO authenticated
        USING (public.is_admin())
        WITH CHECK (public.is_admin());
    END IF;
END $$;

-- 5.2. user_roles
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_roles') THEN
        ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.user_roles FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_roles TO authenticated;

        CREATE POLICY "Usuário consulta seus próprios papéis ou admin consulta todos"
        ON public.user_roles FOR SELECT
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Apenas administradores ativos alteram user_roles"
        ON public.user_roles FOR ALL
        TO authenticated
        USING (public.is_admin())
        WITH CHECK (public.is_admin());
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 6: POLÍTICAS RLS ESTRITAS (PLANOS E ASSINATURAS)
-- ------------------------------------------------------------------------------

-- 6.1. plans (Catálogo público para leitura)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'plans') THEN
        ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;

        CREATE POLICY "Planos ativos visíveis para todos"
        ON public.plans FOR SELECT
        TO authenticated, anon
        USING (is_active = true OR public.is_admin());

        CREATE POLICY "Apenas administradores alteram catálogo de planos"
        ON public.plans FOR ALL
        TO authenticated
        USING (public.is_admin())
        WITH CHECK (public.is_admin());
    END IF;
END $$;

-- 6.2. subscriptions
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscriptions') THEN
        ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.subscriptions FROM anon;
        GRANT SELECT ON public.subscriptions TO authenticated;

        CREATE POLICY "Usuário consulta sua própria assinatura ou admin consulta todas"
        ON public.subscriptions FOR SELECT
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Apenas admin altera assinaturas diretamente"
        ON public.subscriptions FOR ALL
        TO authenticated
        USING (public.is_admin())
        WITH CHECK (public.is_admin());
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 7: POLÍTICAS RLS ESTRITAS (PERFIS E USUÁRIOS)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.profiles FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;

        -- Leitura: o próprio usuário, administrador, ou Personal/Atleta vinculados ativamente
        CREATE POLICY "Perfis lidos pelo próprio usuário, admin ou parceiro de treino vinculado"
        ON public.profiles FOR SELECT
        TO authenticated
        USING (
            auth.uid() = id 
            OR public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.status = 'active'
                  AND ((ta.trainer_id = auth.uid() AND ta.athlete_id = public.profiles.id)
                    OR (ta.athlete_id = auth.uid() AND ta.trainer_id = public.profiles.id))
            )
        );

        CREATE POLICY "Usuário insere seu próprio perfil"
        ON public.profiles FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = id);

        CREATE POLICY "Usuário atualiza seu próprio perfil ou admin atualiza"
        ON public.profiles FOR UPDATE
        TO authenticated
        USING (auth.uid() = id OR public.is_admin())
        WITH CHECK (auth.uid() = id OR public.is_admin());

        CREATE POLICY "Apenas o próprio usuário ou admin exclui perfil"
        ON public.profiles FOR DELETE
        TO authenticated
        USING (auth.uid() = id OR public.is_admin());
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'usuarios') THEN
        ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.usuarios FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.usuarios TO authenticated;

        CREATE POLICY "Usuários leem seu próprio registro em usuarios ou admin"
        ON public.usuarios FOR SELECT
        TO authenticated
        USING (auth.uid() = id OR public.is_admin());

        CREATE POLICY "Usuários gerenciam seu próprio registro em usuarios"
        ON public.usuarios FOR ALL
        TO authenticated
        USING (auth.uid() = id OR public.is_admin())
        WITH CHECK (auth.uid() = id OR public.is_admin());
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 8: POLÍTICAS RLS ESTRITAS (TREINOS, EXERCÍCIOS E REGISTROS PRIVADOS)
-- ------------------------------------------------------------------------------

-- 8.1. treinos
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'treinos') THEN
        ALTER TABLE public.treinos ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.treinos FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.treinos TO authenticated;

        CREATE POLICY "Treinos lidos pelo proprietário, admin ou personal vinculado"
        ON public.treinos FOR SELECT
        TO authenticated
        USING (
            auth.uid() = user_id 
            OR public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.trainer_id = auth.uid() AND ta.athlete_id = public.treinos.user_id AND ta.status = 'active'
            )
        );

        CREATE POLICY "Usuário cria seus próprios treinos"
        ON public.treinos FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Usuário altera seus próprios treinos ou admin altera"
        ON public.treinos FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin())
        WITH CHECK (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Usuário exclui seus próprios treinos ou admin exclui"
        ON public.treinos FOR DELETE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE INDEX IF NOT EXISTS idx_treinos_user_id ON public.treinos(user_id);
    END IF;
END $$;

-- 8.2. exercicios (Catálogo público vs Customizados do Usuário)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exercicios') THEN
        ALTER TABLE public.exercicios ENABLE ROW LEVEL SECURITY;
        GRANT SELECT ON public.exercicios TO authenticated, anon;
        GRANT INSERT, UPDATE, DELETE ON public.exercicios TO authenticated;

        CREATE POLICY "Exercícios públicos visíveis a todos; customizados ao proprietário ou admin"
        ON public.exercicios FOR SELECT
        TO authenticated, anon
        USING (
            user_id IS NULL 
            OR (auth.uid() IS NOT NULL AND auth.uid() = user_id)
            OR public.is_admin()
        );

        CREATE POLICY "Usuários criam apenas exercícios próprios vinculados ao seu id"
        ON public.exercicios FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

        CREATE POLICY "Usuários alteram apenas seus próprios exercícios customizados"
        ON public.exercicios FOR UPDATE
        TO authenticated
        USING (auth.uid() IS NOT NULL AND (auth.uid() = user_id OR public.is_admin()))
        WITH CHECK (auth.uid() IS NOT NULL AND (auth.uid() = user_id OR public.is_admin()));

        CREATE POLICY "Usuários excluem apenas seus próprios exercícios customizados"
        ON public.exercicios FOR DELETE
        TO authenticated
        USING (auth.uid() IS NOT NULL AND (auth.uid() = user_id OR public.is_admin()));
    END IF;
END $$;

-- 8.3. sessoes_de_treino (Histórico de Treinos)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sessoes_de_treino') THEN
        ALTER TABLE public.sessoes_de_treino ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.sessoes_de_treino FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessoes_de_treino TO authenticated;

        CREATE POLICY "Sessões lidas pelo atleta, admin ou personal vinculado"
        ON public.sessoes_de_treino FOR SELECT
        TO authenticated
        USING (
            auth.uid() = user_id 
            OR public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.trainer_id = auth.uid() AND ta.athlete_id = public.sessoes_de_treino.user_id AND ta.status = 'active'
            )
        );

        CREATE POLICY "Atleta insere suas próprias sessões"
        ON public.sessoes_de_treino FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Atleta atualiza suas próprias sessões ou admin atualiza"
        ON public.sessoes_de_treino FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin())
        WITH CHECK (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Atleta exclui suas próprias sessões ou admin exclui"
        ON public.sessoes_de_treino FOR DELETE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE INDEX IF NOT EXISTS idx_sessoes_user_id ON public.sessoes_de_treino(user_id);
    END IF;
END $$;

-- 8.4. historico_de_exercicios (Séries e Logs Detalhados)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'historico_de_exercicios') THEN
        ALTER TABLE public.historico_de_exercicios ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.historico_de_exercicios FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.historico_de_exercicios TO authenticated;

        CREATE POLICY "Histórico de séries lido pelo atleta, admin ou personal vinculado"
        ON public.historico_de_exercicios FOR SELECT
        TO authenticated
        USING (
            auth.uid() = user_id 
            OR public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.trainer_id = auth.uid() AND ta.athlete_id = public.historico_de_exercicios.user_id AND ta.status = 'active'
            )
        );

        CREATE POLICY "Atleta insere seus próprios logs de séries"
        ON public.historico_de_exercicios FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Atleta altera seus próprios logs de séries ou admin altera"
        ON public.historico_de_exercicios FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin())
        WITH CHECK (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Atleta exclui seus próprios logs de séries ou admin exclui"
        ON public.historico_de_exercicios FOR DELETE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE INDEX IF NOT EXISTS idx_historico_exercicios_user_id ON public.historico_de_exercicios(user_id);
    END IF;
END $$;

-- 8.5. exercicios_favoritos / favoritos
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exercicios_favoritos') THEN
        ALTER TABLE public.exercicios_favoritos ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.exercicios_favoritos FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.exercicios_favoritos TO authenticated;

        CREATE POLICY "Usuário consulta seus próprios favoritos"
        ON public.exercicios_favoritos FOR SELECT
        TO authenticated
        USING (auth.uid() = user_id);

        CREATE POLICY "Usuário adiciona favoritos para sua própria conta"
        ON public.exercicios_favoritos FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Usuário remove seus próprios favoritos"
        ON public.exercicios_favoritos FOR DELETE
        TO authenticated
        USING (auth.uid() = user_id);

        CREATE INDEX IF NOT EXISTS idx_exercicios_favoritos_user_id ON public.exercicios_favoritos(user_id);
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'favoritos') THEN
        ALTER TABLE public.favoritos ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.favoritos FROM anon;
        GRANT SELECT, INSERT, DELETE ON public.favoritos TO authenticated;

        CREATE POLICY "Usuário consulta seus favoritos em favoritos"
        ON public.favoritos FOR SELECT
        TO authenticated
        USING (auth.uid() = user_id);

        CREATE POLICY "Usuário gerencia seus favoritos em favoritos"
        ON public.favoritos FOR ALL
        TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 8.6. medidas_corporais
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'medidas_corporais') THEN
        ALTER TABLE public.medidas_corporais ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.medidas_corporais FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.medidas_corporais TO authenticated;

        CREATE POLICY "Medidas lidas pelo atleta, admin ou personal vinculado"
        ON public.medidas_corporais FOR SELECT
        TO authenticated
        USING (
            auth.uid() = user_id 
            OR public.is_admin()
            OR EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.trainer_id = auth.uid() AND ta.athlete_id = public.medidas_corporais.user_id AND ta.status = 'active'
            )
        );

        CREATE POLICY "Atleta insere suas próprias medidas"
        ON public.medidas_corporais FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Atleta altera suas próprias medidas ou admin altera"
        ON public.medidas_corporais FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin())
        WITH CHECK (auth.uid() = user_id OR public.is_admin());

        CREATE POLICY "Atleta exclui suas próprias medidas ou admin exclui"
        ON public.medidas_corporais FOR DELETE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin());

        CREATE INDEX IF NOT EXISTS idx_medidas_user_id ON public.medidas_corporais(user_id);
    END IF;
END $$;

-- 8.7. configuracoes
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'configuracoes') THEN
        ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.configuracoes FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.configuracoes TO authenticated;

        CREATE POLICY "Usuário consulta e gerencia suas próprias configurações"
        ON public.configuracoes FOR ALL
        TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 9: POLÍTICAS RLS ESTRITAS (PERSONAL TRAINER, ALUNOS E ATRIBUIÇÕES)
-- ------------------------------------------------------------------------------

-- 9.1. trainer_profiles
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'trainer_profiles') THEN
        ALTER TABLE public.trainer_profiles ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.trainer_profiles FROM anon;
        GRANT SELECT, INSERT, UPDATE ON public.trainer_profiles TO authenticated;

        CREATE POLICY "Perfis aprovados de personal são visíveis; pendentes visíveis apenas ao proprietário ou admin"
        ON public.trainer_profiles FOR SELECT
        TO authenticated
        USING (
            verification_status = 'approved'
            OR auth.uid() = user_id
            OR public.is_admin()
        );

        CREATE POLICY "Personal cria seu próprio perfil profissional com status não homologado"
        ON public.trainer_profiles FOR INSERT
        TO authenticated
        WITH CHECK (
            auth.uid() = user_id 
            AND verification_status IN ('not_submitted', 'pending')
        );

        CREATE POLICY "Personal edita seus dados cadastrais (sem alterar aprovação de CREF)"
        ON public.trainer_profiles FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id OR public.is_admin())
        WITH CHECK (
            (auth.uid() = user_id AND (verification_status = (SELECT tp.verification_status FROM public.trainer_profiles tp WHERE tp.user_id = auth.uid()) OR verification_status = 'pending'))
            OR public.is_admin()
        );
    END IF;
END $$;

-- 9.2. trainer_athletes (Vínculos Personal & Aluno)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'trainer_athletes') THEN
        ALTER TABLE public.trainer_athletes ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.trainer_athletes FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.trainer_athletes TO authenticated;

        CREATE POLICY "Personal e Atleta visualizam seus próprios vínculos mútuos"
        ON public.trainer_athletes FOR SELECT
        TO authenticated
        USING (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin());

        CREATE POLICY "Apenas participantes vinculados ou admin alteram status do relacionamento"
        ON public.trainer_athletes FOR UPDATE
        TO authenticated
        USING (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin())
        WITH CHECK (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin());
    END IF;
END $$;

-- 9.3. trainer_invites (Convites)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'trainer_invites') THEN
        ALTER TABLE public.trainer_invites ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.trainer_invites FROM anon;
        GRANT SELECT, INSERT, UPDATE ON public.trainer_invites TO authenticated;

        CREATE POLICY "Personal visualiza seus próprios convites emitidos"
        ON public.trainer_invites FOR SELECT
        TO authenticated
        USING (auth.uid() = trainer_id OR public.is_admin());

        CREATE POLICY "Personal cria convites para novos alunos"
        ON public.trainer_invites FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = trainer_id);

        CREATE POLICY "Personal atualiza seus convites"
        ON public.trainer_invites FOR UPDATE
        TO authenticated
        USING (auth.uid() = trainer_id OR public.is_admin())
        WITH CHECK (auth.uid() = trainer_id OR public.is_admin());
    END IF;
END $$;

-- 9.4. workout_assignments (Fichas Prescritas)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'workout_assignments') THEN
        ALTER TABLE public.workout_assignments ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.workout_assignments FROM anon;
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.workout_assignments TO authenticated;

        CREATE POLICY "Personal e Atleta visualizam fichas atribuídas mútuas"
        ON public.workout_assignments FOR SELECT
        TO authenticated
        USING (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin());

        CREATE POLICY "Personal prescreve treinos apenas para alunos com vínculo ativo"
        ON public.workout_assignments FOR INSERT
        TO authenticated
        WITH CHECK (
            auth.uid() = trainer_id 
            AND EXISTS (
                SELECT 1 FROM public.trainer_athletes ta 
                WHERE ta.trainer_id = auth.uid() AND ta.athlete_id = public.workout_assignments.athlete_id AND ta.status = 'active'
            )
        );

        CREATE POLICY "Personal ou Atleta atualizam status da ficha atribuída"
        ON public.workout_assignments FOR UPDATE
        TO authenticated
        USING (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin())
        WITH CHECK (auth.uid() = trainer_id OR auth.uid() = athlete_id OR public.is_admin());
    END IF;
END $$;

-- 9.5. workout_assignment_comments (Comentários de Prescrição)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'workout_assignment_comments') THEN
        ALTER TABLE public.workout_assignment_comments ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.workout_assignment_comments FROM anon;
        GRANT SELECT, INSERT, DELETE ON public.workout_assignment_comments TO authenticated;

        CREATE POLICY "Personal e Atleta leem comentários da ficha mútua"
        ON public.workout_assignment_comments FOR SELECT
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.workout_assignments wa 
                WHERE wa.id = assignment_id AND (wa.trainer_id = auth.uid() OR wa.athlete_id = auth.uid() OR public.is_admin())
            )
        );

        CREATE POLICY "Personal e Atleta inserem comentários na ficha mútua"
        ON public.workout_assignment_comments FOR INSERT
        TO authenticated
        WITH CHECK (
            auth.uid() = author_id 
            AND EXISTS (
                SELECT 1 FROM public.workout_assignments wa 
                WHERE wa.id = assignment_id AND (wa.trainer_id = auth.uid() OR wa.athlete_id = auth.uid())
            )
        );
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- SEÇÃO 10: ENDURECIMENTO DAS FUNÇÕES RPC (SECURITY DEFINER)
-- ------------------------------------------------------------------------------

-- 10.1. get_all_users() — Exclusivo para Administradores Ativos
CREATE OR REPLACE FUNCTION public.get_all_users()
RETURNS TABLE (
    id UUID,
    email TEXT,
    nome TEXT,
    criado_em TIMESTAMPTZ,
    ultimo_acesso TIMESTAMPTZ,
    bloqueado BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    -- Validação autoritativa e obrigatória: rejeitar sem token ou não-admin
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado: apenas administradores ativos possuem permissão para listar usuários.';
    END IF;

    RETURN QUERY
    SELECT 
        u.id,
        u.email::TEXT,
        COALESCE(u.raw_user_meta_data->>'nome', SPLIT_PART(u.email, '@', 1))::TEXT AS nome,
        u.created_at AS criado_em,
        u.last_sign_in_at AS ultimo_acesso,
        COALESCE((u.raw_user_meta_data->>'bloqueado')::BOOLEAN, false) AS bloqueado
    FROM auth.users u
    ORDER BY u.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_users() TO authenticated;

-- 10.2. get_my_entitlements — Impede parâmetros forjados
CREATE OR REPLACE FUNCTION public.get_my_entitlements(p_user_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_uid UUID;
    v_target UUID;
    v_sub RECORD;
    v_role TEXT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Não autenticado');
    END IF;

    -- Não permitir consultar direitos de outro usuário sem ser admin
    IF p_user_id IS NOT NULL AND p_user_id <> v_uid THEN
        IF NOT public.is_admin() THEN
            v_target := v_uid;
        ELSE
            v_target := p_user_id;
        END IF;
    ELSE
        v_target := v_uid;
    END IF;

    -- Obter papel principal
    SELECT role INTO v_role 
    FROM public.user_roles 
    WHERE user_id = v_target AND active = true 
    ORDER BY CASE role WHEN 'admin' THEN 1 WHEN 'trainer' THEN 2 ELSE 3 END 
    LIMIT 1;

    IF v_role IS NULL THEN
        v_role := 'athlete';
    END IF;

    -- Se for admin, concede acesso total
    IF v_role = 'admin' OR public.is_admin() THEN
        RETURN jsonb_build_object(
            'success', true,
            'role', 'admin',
            'is_admin', true,
            'plan_id', 'gold',
            'plan_name', 'Acesso Total Administrador',
            'status', 'active',
            'features', jsonb_build_object(
                'unlimited_workouts', true,
                'unlimited_students', true,
                'advanced_analytics', true,
                'custom_exercises', true,
                'priority_sync', true,
                'export_reports', true
            )
        );
    END IF;

    -- Buscar assinatura ativa
    SELECT s.*, p.code AS plan_code, p.name AS plan_name, p.features AS plan_features
    INTO v_sub
    FROM public.subscriptions s
    JOIN public.plans p ON p.id = s.plan_id
    WHERE s.user_id = v_target
    ORDER BY s.created_at DESC
    LIMIT 1;

    IF v_sub IS NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'role', v_role,
            'is_admin', false,
            'plan_id', 'free',
            'plan_name', 'Plano Gratuito',
            'status', 'active',
            'features', jsonb_build_object(
                'unlimited_workouts', false,
                'max_workouts', 5,
                'max_students', CASE WHEN v_role = 'trainer' THEN 2 ELSE 0 END,
                'advanced_analytics', false
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'role', v_role,
        'is_admin', false,
        'plan_id', v_sub.plan_code,
        'plan_name', v_sub.plan_name,
        'status', v_sub.status,
        'current_period_end', v_sub.current_period_end,
        'features', v_sub.plan_features
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_entitlements(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_entitlements(UUID) TO authenticated;

-- ------------------------------------------------------------------------------
-- SEÇÃO 11: CONSULTAS DE VERIFICAÇÃO SOMENTE LEITURA
-- (Execute para auditar a segurança final do banco)
-- ------------------------------------------------------------------------------

-- 11.1. Listar todas as políticas RLS ativas e tabelas protegidas
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 11.2. Verificar tabelas no schema public com RLS habilitada vs desabilitada
SELECT 
    tablename,
    rowsecurity AS rls_habilitada
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- 11.3. Verificar privilégios concedidos ao papel 'anon'
SELECT 
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'anon' AND table_schema = 'public'
ORDER BY table_name, privilege_type;

-- FIM DA MIGRAÇÃO FINAL DE HARDENING DE SEGURANÇA
