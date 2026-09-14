-- ====================================================================
-- TITANNOVA FIT — FASE 1: HARDENING DE SEGURANÇA E RLS ESTRITA
-- Migração Segura e Não-Destrutiva
-- Data: 2026-09-03
-- ====================================================================

-- 1. GARANTIR EXTENSÃO UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TABELA DE AUDITORIA DE ACEITES LEGAIS (LGPD, IDADE MÍNIMA E CONSENTIMENTO)
CREATE TABLE IF NOT EXISTS public.legal_acceptances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    terms_version TEXT NOT NULL DEFAULT '1.0',
    privacy_version TEXT NOT NULL DEFAULT '1.0',
    terms_accepted BOOLEAN NOT NULL DEFAULT false,
    privacy_acknowledged BOOLEAN NOT NULL DEFAULT false,
    age_requirement_confirmed BOOLEAN NOT NULL DEFAULT false,
    guardian_authorization_confirmed BOOLEAN NOT NULL DEFAULT false,
    analytics_consent BOOLEAN DEFAULT false,
    platform TEXT DEFAULT 'web',
    language TEXT DEFAULT 'pt-BR',
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.legal_acceptances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuário consulta seus próprios aceites" ON public.legal_acceptances;
CREATE POLICY "Usuário consulta seus próprios aceites"
ON public.legal_acceptances FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Usuário registra seus próprios aceites" ON public.legal_acceptances;
CREATE POLICY "Usuário registra seus próprios aceites"
ON public.legal_acceptances FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_legal_acceptances_user_id ON public.legal_acceptances(user_id);
CREATE INDEX IF NOT EXISTS idx_legal_acceptances_accepted_at ON public.legal_acceptances(accepted_at DESC);

-- 3. RLS ESTRITA EM PROFILES (SEM PERMISSÃO ANÔNIMA)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuarios gerenciam seu proprio perfil em profiles" ON public.profiles;
DROP POLICY IF EXISTS "Usuário visualiza seu perfil" ON public.profiles;
DROP POLICY IF EXISTS "Usuário atualiza seu perfil" ON public.profiles;
DROP POLICY IF EXISTS "Usuário insere seu perfil" ON public.profiles;

CREATE POLICY "Usuário visualiza seu perfil"
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Usuário insere seu perfil"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY "Usuário atualiza seu perfil"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 4. RLS ESTRITA EM TREINOS (WORKOUTS)
ALTER TABLE public.treinos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuarios gerenciam seus proprios treinos" ON public.treinos;
DROP POLICY IF EXISTS "Usuário visualiza seus treinos" ON public.treinos;
DROP POLICY IF EXISTS "Usuário cria seus treinos" ON public.treinos;
DROP POLICY IF EXISTS "Usuário altera seus treinos" ON public.treinos;
DROP POLICY IF EXISTS "Usuário exclui seus treinos" ON public.treinos;

CREATE POLICY "Usuário visualiza seus treinos"
ON public.treinos FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Usuário cria seus treinos"
ON public.treinos FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário altera seus treinos"
ON public.treinos FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário exclui seus treinos"
ON public.treinos FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_treinos_user_id ON public.treinos(user_id);

-- 5. RLS ESTRITA EM SESSÕES DE TREINO (HISTÓRICO)
ALTER TABLE public.sessoes_de_treino ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuarios gerenciam suas proprias sessoes" ON public.sessoes_de_treino;
DROP POLICY IF EXISTS "Usuário visualiza suas sessões" ON public.sessoes_de_treino;
DROP POLICY IF EXISTS "Usuário cria suas sessões" ON public.sessoes_de_treino;
DROP POLICY IF EXISTS "Usuário altera suas sessões" ON public.sessoes_de_treino;
DROP POLICY IF EXISTS "Usuário exclui suas sessões" ON public.sessoes_de_treino;

CREATE POLICY "Usuário visualiza suas sessões"
ON public.sessoes_de_treino FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Usuário cria suas sessões"
ON public.sessoes_de_treino FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário altera suas sessões"
ON public.sessoes_de_treino FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário exclui suas sessões"
ON public.sessoes_de_treino FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_sessoes_user_id ON public.sessoes_de_treino(user_id);

-- 6. RLS ESTRITA EM FAVORITOS
ALTER TABLE public.exercicios_favoritos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuarios gerenciam seus favoritos" ON public.exercicios_favoritos;
DROP POLICY IF EXISTS "Usuário visualiza seus favoritos" ON public.exercicios_favoritos;
DROP POLICY IF EXISTS "Usuário adiciona favoritos" ON public.exercicios_favoritos;
DROP POLICY IF EXISTS "Usuário remove favoritos" ON public.exercicios_favoritos;

CREATE POLICY "Usuário visualiza seus favoritos"
ON public.exercicios_favoritos FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Usuário adiciona favoritos"
ON public.exercicios_favoritos FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário remove favoritos"
ON public.exercicios_favoritos FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_favoritos_user_id ON public.exercicios_favoritos(user_id);

-- 7. RLS ESTRITA EM MEDIDAS CORPORAIS
CREATE TABLE IF NOT EXISTS public.medidas_corporais (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID DEFAULT gen_random_uuid(),
  peso NUMERIC(5,2),
  altura NUMERIC(5,2),
  braco_direito NUMERIC(5,2),
  braco_esquerdo NUMERIC(5,2),
  peito NUMERIC(5,2),
  cintura NUMERIC(5,2),
  coxa_direita NUMERIC(5,2),
  coxa_esquerda NUMERIC(5,2),
  observacoes TEXT,
  data TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.medidas_corporais ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Usuário visualiza suas medidas" ON public.medidas_corporais;
DROP POLICY IF EXISTS "Usuário cria suas medidas" ON public.medidas_corporais;
DROP POLICY IF EXISTS "Usuário atualiza suas medidas" ON public.medidas_corporais;
DROP POLICY IF EXISTS "Usuário exclui suas medidas" ON public.medidas_corporais;

CREATE POLICY "Usuário visualiza suas medidas"
ON public.medidas_corporais FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Usuário cria suas medidas"
ON public.medidas_corporais FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário atualiza suas medidas"
ON public.medidas_corporais FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Usuário exclui suas medidas"
ON public.medidas_corporais FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_medidas_user_id ON public.medidas_corporais(user_id);

-- 8. CATÁLOGO PÚBLICO DE EXERCÍCIOS (EXERCISEDB V1) - LEITURA PÚBLICA / ESCRITA ADMIN
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir leitura pública de exercises" ON public.exercises;
DROP POLICY IF EXISTS "Administradores gerenciam exercises" ON public.exercises;

CREATE POLICY "Permitir leitura pública de exercises"
ON public.exercises FOR SELECT
TO authenticated, anon
USING (true);

-- 9. SÉRIES REALIZADAS
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'series_realizadas') THEN
    ALTER TABLE public.series_realizadas ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Usuarios gerenciam suas proprias series" ON public.series_realizadas;
    CREATE POLICY "Usuarios gerenciam suas proprias series"
    ON public.series_realizadas FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
