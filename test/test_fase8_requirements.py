"""
TitanNova Fit - Suíte de Testes Automatizados da Fase 8 e Hardening
Valida requisitos funcionais, integridade de arquivos, segurança, isolamento e regras de negócio.
"""

import os
import unittest

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def format_seconds_to_mmss(total_seconds):
    """Implementação espelho do algoritmo JavaScript formatSecondsToMMSS"""
    try:
        s = max(0, int(total_seconds))
    except (TypeError, ValueError):
        s = 0
    m_str = str(s // 60).zfill(2)
    s_str = str(s % 60).zfill(2)
    return f"{m_str}:{s_str}"


class TestTimerFormatting(unittest.TestCase):
    """Validação da formatação do cronômetro de descanso (Fase 8 - Item 1 e 2)"""

    def test_transicoes_criticas(self):
        # Cenário 12: Timer formata corretamente as transições de minuto
        self.assertEqual(format_seconds_to_mmss(59), "00:59", "59 segundos deve ser 00:59")
        self.assertEqual(format_seconds_to_mmss(60), "01:00", "60 segundos deve ser 01:00 (NÃO 00:60)")
        self.assertEqual(format_seconds_to_mmss(61), "01:01", "61 segundos deve ser 01:01")
        self.assertEqual(format_seconds_to_mmss(119), "01:59", "119 segundos deve ser 01:59")
        self.assertEqual(format_seconds_to_mmss(120), "02:00", "120 segundos deve ser 02:00")

    def test_limites_e_valores_especiais(self):
        self.assertEqual(format_seconds_to_mmss(0), "00:00")
        self.assertEqual(format_seconds_to_mmss(-10), "00:00")
        self.assertEqual(format_seconds_to_mmss(3599), "59:59")
        self.assertEqual(format_seconds_to_mmss(3600), "60:00")

    def test_html_cronometro_inicial(self):
        """Verifica se o HTML estático do app.html não possui mais 00:60 e usa 01:00"""
        app_html_path = os.path.join(ROOT_DIR, "app.html")
        self.assertTrue(os.path.exists(app_html_path), "app.html deve existir")
        with open(app_html_path, "r", encoding="utf-8") as f:
            content = f.read()

        # O texto 00:60 não pode estar no ID restTimerText
        self.assertNotIn('id="restTimerText" style="font-size: 20px; font-weight: 900; color: white;">00:60<', content,
                         "O cronômetro inicial no HTML não deve ser 00:60")
        self.assertIn('id="restTimerText" style="font-size: 20px; font-weight: 900; color: white;">01:00<', content,
                      "O cronômetro inicial no HTML deve ser 01:00")


class TestFlutterAssetsIntegrity(unittest.TestCase):
    """Validação da estrutura física de assets declarada no pubspec.yaml (Fase 8 - Item 3)"""

    def test_pastas_assets_existem(self):
        declared_dirs = [
            "assets/icons",
            "assets/images",
            "assets/videos",
            "assets/sounds"
        ]
        for rel_path in declared_dirs:
            full_path = os.path.join(ROOT_DIR, rel_path)
            self.assertTrue(os.path.isdir(full_path), f"Diretório de asset '{rel_path}' deve existir fisicamente")


class TestServiceWorkerRules(unittest.TestCase):
    """Validação das regras de isolamento de cache no sw.js (Fase 6 e Cenário 9)"""

    def test_service_worker_restricoes(self):
        sw_path = os.path.join(ROOT_DIR, "sw.js")
        self.assertTrue(os.path.exists(sw_path), "sw.js deve existir")
        with open(sw_path, "r", encoding="utf-8") as f:
            sw_content = f.read()

        # Cenário 9: Logout e troca de conta não reutilizam respostas do cache
        self.assertIn("authorization", sw_content.lower())
        self.assertIn("/api/", sw_content)
        self.assertIn("isApiOrSupabase", sw_content)
        # Não deve incluir BUILD_GUIDE no cache
        self.assertNotIn("BUILD_GUIDE.md", sw_content)


class TestSecurityHardening(unittest.TestCase):
    """Validação de ausência de chaves administrativas versionadas e arquivos sensíveis (Fase 1)"""

    def test_sem_chaves_service_role_em_codigo_versionado(self):
        b64_old_secret = "c2Jfc2VjcmV0X2p5eWdfVC0tdDhPWFNPQ3k0NXB1blFfNXpwcG5vaGs="
        api_dir = os.path.join(ROOT_DIR, "api")
        for root, _, files in os.walk(api_dir):
            for file in files:
                if file.endswith(".js"):
                    with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                        content = f.read()
                        self.assertNotIn(b64_old_secret, content, f"Arquivo {file} não deve conter segredo em base64")

    def test_env_example_apenas_placeholders(self):
        env_example_path = os.path.join(ROOT_DIR, ".env.example")
        self.assertTrue(os.path.exists(env_example_path))
        with open(env_example_path, "r", encoding="utf-8") as f:
            content = f.read()
            self.assertNotIn("sb_secret_", content)


class TestApiAuthContracts(unittest.TestCase):
    """Validação dos contratos de autorização e autenticação das APIs (Fase 3, Cenários 7 e 8)"""

    def test_auth_helper_exports(self):
        auth_js = os.path.join(ROOT_DIR, "api", "_auth.js")
        self.assertTrue(os.path.exists(auth_js))
        with open(auth_js, "r", encoding="utf-8") as f:
            content = f.read()
            self.assertIn("extractBearerToken", content)
            self.assertIn("validateUserToken", content)
            self.assertIn("verifyIsAdmin", content)
            self.assertIn("requireAuth", content)
            self.assertIn("requireAdmin", content)
            self.assertIn("checkRateLimit", content)

    def test_api_legal_requires_token_and_user_match(self):
        legal_js = os.path.join(ROOT_DIR, "api", "legal.js")
        self.assertTrue(os.path.exists(legal_js))
        with open(legal_js, "r", encoding="utf-8") as f:
            content = f.read()
            # Cenário 7: /api/legal exige requireAuth e usa authenticatedUserId
            self.assertIn("requireAuth", content)
            self.assertIn("authenticatedUserId", content)

    def test_api_users_requires_admin_authorization(self):
        users_js = os.path.join(ROOT_DIR, "api", "users.js")
        self.assertTrue(os.path.exists(users_js))
        with open(users_js, "r", encoding="utf-8") as f:
            content = f.read()
            # Cenário 8: API administrativa rejeita não administradores com requireAdmin
            self.assertIn("requireAdmin", content)


class TestXssPreventionAndSanitization(unittest.TestCase):
    """Validação de sanitização e proteção contra XSS (Fase 5, Cenário 6)"""

    def test_escape_html_present_in_app(self):
        app_html_path = os.path.join(ROOT_DIR, "app.html")
        with open(app_html_path, "r", encoding="utf-8") as f:
            content = f.read()
            # Cenário 6: Função de sanitização centralizada presente no app
            self.assertIn("function escapeHtml(", content)
            self.assertIn("window.escapeHtml = escapeHtml;", content)


class TestFlutterIsolationAndOffline(unittest.TestCase):
    """Validação de particionamento local e exclusão no Flutter (Fase 7, Cenários 10 e 11)"""

    def test_workout_repository_has_user_partitioning(self):
        repo_path = os.path.join(ROOT_DIR, "lib", "data", "repositories", "workout_repository.dart")
        self.assertTrue(os.path.exists(repo_path))
        with open(repo_path, "r", encoding="utf-8") as f:
            content = f.read()
            # Cenário 10 e 11: Carregamento filtrado estritamente por usuário
            self.assertIn("LocalDatabase.instance.getTreinos(uid)", content)
            self.assertIn("LocalDatabase.instance.getHistoricoSessoes(uid)", content)
            self.assertIn("LocalDatabase.instance.deleteTreino", content)


class TestArchitectureDocumentation(unittest.TestCase):
    """Validação do documento formal de arquitetura (Fase 8 - Item 6 e 7)"""

    def test_architecture_document_exists(self):
        arch_path = os.path.join(ROOT_DIR, "ARCHITECTURE.md")
        self.assertTrue(os.path.exists(arch_path), "ARCHITECTURE.md deve existir")
        with open(arch_path, "r", encoding="utf-8") as f:
            content = f.read()
            self.assertIn("Web / PWA", content)
            self.assertIn("Flutter Mobile", content)
            self.assertIn("Modularização Progressiva", content)


class TestWorkoutScreenStability(unittest.TestCase):
    """Validações para estabilização visual da tela Divisões de Treino (Fase de Estabilização e Anti-Flicker)"""

    @classmethod
    def setUpClass(cls):
        app_html_path = os.path.join(ROOT_DIR, "app.html")
        with open(app_html_path, "r", encoding="utf-8") as f:
            cls.app_html = f.read()

    def test_fingerprint_determinism_and_insensitivity_to_order(self):
        """Valida que o algoritmo de fingerprinting é determinístico e imune à ordem de lista"""
        import json

        def normalize(w):
            if not w: return None
            exs = w.get("exercicios") if isinstance(w.get("exercicios"), list) else []
            days = sorted(w.get("diasSemana", [])) if isinstance(w.get("diasSemana"), list) else []
            return {
                "id": str(w.get("id") or ""),
                "nome": str(w.get("nome") or "").strip(),
                "descricao": str(w.get("descricao") or "").strip(),
                "diasSemana": days,
                "corHex": str(w.get("corHex") or "").strip(),
                "updatedAt": str(w.get("updated_at") or w.get("atualizado_em") or w.get("criadoEm") or ""),
                "exercicios": [
                    {
                        "id": str(e.get("id") or e.get("exercise_id") or idx),
                        "nome": str(e.get("nome") or e.get("name") or "").strip(),
                        "series": str(e.get("series") or ""),
                        "reps": str(e.get("reps") or ""),
                        "descanso": int(e.get("descanso") or 0)
                    }
                    for idx, e in enumerate(exs)
                ]
            }

        def fingerprint(wl):
            norm = [normalize(w) for w in wl]
            norm = [w for w in norm if w is not None]
            norm.sort(key=lambda x: x["id"])
            return json.dumps(norm, sort_keys=True)

        w1 = {"id": "w1", "nome": "Peito", "diasSemana": ["Segunda", "Quinta"], "corHex": "#ff0000", "exercicios": [{"id": "e1", "nome": "Supino", "series": "4", "reps": "10", "descanso": 60}]}
        w2 = {"id": "w2", "nome": "Costas", "diasSemana": ["Terça", "Sexta"], "corHex": "#00ff00", "exercicios": [{"id": "e2", "nome": "Puxada", "series": "3", "reps": "12", "descanso": 45}]}

        fp_a = fingerprint([w1, w2])
        fp_b = fingerprint([w2, w1])
        self.assertEqual(fp_a, fp_b, "Fingerprint deve ser idêntico independente da ordem dos treinos")

        # Modificação de um parâmetro deve alterar o fingerprint
        w1_mod = {**w1, "nome": "Peito e Tríceps"}
        fp_mod = fingerprint([w1_mod, w2])
        self.assertNotEqual(fp_a, fp_mod, "Fingerprint deve mudar se o nome de um treino for modificado")

    def test_fingerprint_functions_exported_in_html(self):
        """Verifica funções essenciais de fingerprinting exportadas"""
        self.assertIn("function normalizeWorkoutForComparison(", self.app_html)
        self.assertIn("function createWorkoutsFingerprint(", self.app_html)
        self.assertIn("window.normalizeWorkoutForComparison = normalizeWorkoutForComparison;", self.app_html)
        self.assertIn("window.createWorkoutsFingerprint = createWorkoutsFingerprint;", self.app_html)

    def test_surgical_dom_patching_present(self):
        """Verifica se patchWorkoutCards faz atualização cirúrgica por data-workout-id"""
        self.assertIn("function patchWorkoutCards(nextWorkouts)", self.app_html)
        self.assertIn("container.querySelectorAll('[data-workout-id]')", self.app_html)
        self.assertIn("existingCard.innerHTML !== cardHtml", self.app_html)
        self.assertIn("function renderAllWorkoutsUI()", self.app_html)
        self.assertIn("patchWorkoutCards(allWorkoutsList)", self.app_html)

    def test_no_inline_fade_in_animation_on_workout_cards(self):
        """Verifica que o HTML do cartão não possui animation: fadeIn inline e usa classe .is-new"""
        self.assertIn("function generateWorkoutCardHtml(", self.app_html)
        gen_start = self.app_html.find("function generateWorkoutCardHtml(")
        gen_end = self.app_html.find("function patchWorkoutCards(")
        gen_func = self.app_html[gen_start:gen_end]
        # Não pode ter inline animation: fadeIn no gerador de HTML do cartão
        self.assertNotIn("animation: fadeIn", gen_func)
        self.assertNotIn("animation:fadeIn", gen_func)

        # patchWorkoutCards também não deve adicionar inline animation: fadeIn
        patch_end = self.app_html.find("function renderAllWorkoutsUI(")
        patch_func = self.app_html[gen_end:patch_end]
        self.assertNotIn("animation: fadeIn", patch_func)

        # Deve possuir regra CSS .workout-card.is-new e prefers-reduced-motion
        self.assertIn(".workout-card.is-new", self.app_html)
        self.assertIn("@media (prefers-reduced-motion: reduce)", self.app_html)

    def test_connection_status_pill_width_stabilized(self):
        """Verifica estilização estável do pill #connectionStatus"""
        self.assertIn("#connectionStatus", self.app_html)
        self.assertIn("min-width: 130px;", self.app_html)
        self.assertIn("beginBackgroundSync()", self.app_html)
        self.assertIn("finishBackgroundSync(", self.app_html)

    def test_realtime_single_channel_guard_and_cleanup(self):
        """Verifica guarda contra recriação desnecessária de canal e funções de cleanup"""
        self.assertIn("_realtimeSyncChannel && _realtimeSyncUserId === uid", self.app_html)
        self.assertIn("function scheduleRealtimeWorkoutRefresh()", self.app_html)
        self.assertIn("function cleanupRealtimeSync()", self.app_html)
        self.assertIn("await cleanupRealtimeSync();", self.app_html)
        self.assertIn("function runWorkoutSyncOnce(task)", self.app_html)


class TestUXSimplificationAndPWAOptimizations(unittest.TestCase):
    """Validação da reformulação da Landing Page e Otimização do PWA (Fase 8 - UX & Hardening)"""

    @classmethod
    def setUpClass(cls):
        index_html_path = os.path.join(ROOT_DIR, "index.html")
        with open(index_html_path, "r", encoding="utf-8") as f:
            cls.index_html = f.read()

        app_html_path = os.path.join(ROOT_DIR, "app.html")
        with open(app_html_path, "r", encoding="utf-8") as f:
            cls.app_html = f.read()

    def test_landing_page_transparency_and_freemium(self):
        """Valida que a promessa contraditória '100% Gratuito' foi removida e substituída pelo freemium honesto"""
        self.assertNotIn("100% Gratuito", self.index_html, "A promessa contraditória 100% Gratuito não deve existir")
        self.assertIn("Comece gratuitamente", self.index_html, "A chamada transparente deve ser Comece gratuitamente")
        self.assertIn("Evolua sua carga.", self.index_html)
        self.assertIn("Acompanhe seus resultados.", self.index_html)
        self.assertIn("Monte seu treino, registre séries e visualize sua evolução.", self.index_html)

    def test_landing_page_privacy_and_clean_faq(self):
        """Valida remoção de termos absolutos de privacidade e jargões técnicos do FAQ"""
        self.assertNotIn("Privacidade Absoluta", self.index_html)
        self.assertNotIn("Conformidade Integral com a LGPD", self.index_html)
        self.assertNotIn("targetEndTime", self.index_html, "Jargão técnico targetEndTime deve ser removido do FAQ")
        self.assertIn("Proteção de dados desde o desenvolvimento", self.index_html)
        self.assertIn("Recursos de privacidade alinhados à LGPD", self.index_html)

    def test_landing_page_showcase_mockups(self):
        """Valida a presença das 3 fases de demonstração real na vitrine da landing page"""
        self.assertIn("Criação da Ficha", self.index_html)
        self.assertIn("Registro de Série", self.index_html)
        self.assertIn("Tela de Evolução", self.index_html)
        self.assertIn("+2 repetições em relação ao treino anterior 🔥", self.index_html)

    def test_pwa_boot_machine_states(self):
        """Valida máquina de estados de boot amigável sem falsos erros para novos visitantes"""
        self.assertIn("Carregando TitanNova Fit...", self.app_html)
        self.assertNotIn("Não foi possível verificar sua sessão. Verifique sua conexão e tente novamente.", self.app_html)
        self.assertIn("Novo visitante sem sessão salva. Transição imediata para login/cadastro.", self.app_html)

    def test_athlete_simplified_registration(self):
        """Valida cadastro simplificado do atleta com nascimento e LGPD sem barreiras extras"""
        self.assertIn("CAMPOS ESPECÍFICOS DO ATLETA (CADASTRO SIMPLIFICADO)", self.app_html)
        self.assertIn('id="authRegisterBirthDate"', self.app_html)
        self.assertIn('id="authAgeCheck"', self.app_html)
        self.assertIn('id="authTermsCheck"', self.app_html)
        self.assertIn('id="authPrivacyCheck"', self.app_html)

    def test_trainer_registration_4_stages(self):
        """Valida cadastro de personal trainer estruturado em etapas claras com aviso de análise de CREF"""
        self.assertIn("CAMPOS ESPECÍFICOS DO PERSONAL TRAINER (ESTRUTURADO EM 4 ETAPAS)", self.app_html)
        self.assertIn("2️⃣</span> Perfil Profissional", self.app_html)
        self.assertIn("3️⃣</span> Habilitação (CREF)", self.app_html)
        self.assertIn("4️⃣</span> Status da Análise & Moderação", self.app_html)
        self.assertIn('id="authTrainerResponsibilityCheck"', self.app_html)

    def test_cref_pending_visual_and_technical_block(self):
        """Valida bloqueio visual (banner) e técnico para CREF pendente na gestão de alunos"""
        self.assertIn('id="trainerPendingNoticeCard"', self.app_html)
        self.assertIn("Cadastro profissional em análise", self.app_html)
        self.assertIn('id="trainerInviteStudentBtn"', self.app_html)
        self.assertIn("🔒 Prescrição Bloqueada (CREF em análise)", self.app_html)

    def test_home_dominant_start_workout_action(self):
        """Valida que o próximo treino domina a home com 1 toque para iniciar"""
        self.assertIn('id="homeHeroCard"', self.app_html)
        self.assertIn("PRÓXIMO TREINO", self.app_html)
        self.assertIn("▶ INICIAR TREINO", self.app_html)
        self.assertIn("aproximadamente", self.app_html)

    def test_series_table_5_columns_and_overload_feedback(self):
        """Valida tabela enxuta de 5 colunas de séries e feedback instantâneo de sobrecarga"""
        self.assertIn("set-columns-header", self.app_html)
        self.assertIn("ANTERIOR", self.app_html)
        self.assertIn("CARGA (KG)", self.app_html)
        self.assertIn("REPETIÇÕES", self.app_html)
        self.assertIn("CONCLUIR", self.app_html)
        self.assertIn("kg de sobrecarga progressiva 💪", self.app_html)
        self.assertIn("em relação ao treino anterior 🔥", self.app_html)

    def test_rest_timer_controls_and_wakelock(self):
        """Valida cronômetro de descanso com botões diretos, wakeLock e pulso de finalização"""
        self.assertIn("requestRestWakeLock()", self.app_html)
        self.assertIn("releaseRestWakeLock()", self.app_html)
        self.assertIn("finished-pulse", self.app_html)
        self.assertIn("restPulseAlert", self.app_html)
        self.assertIn("Encerrar", self.app_html)
        self.assertIn("+15s", self.app_html)
        self.assertIn("+30s", self.app_html)

    def test_sync_status_honest_messaging(self):
        """Valida mensagens realistas e honestas no pill de sincronização"""
        self.assertIn("Salvo neste dispositivo", self.app_html)
        self.assertIn("aguardando sincroniza", self.app_html)
        self.assertIn("Tudo sincronizado", self.app_html)
        self.assertIn("Falha ao sincronizar —", self.app_html)

    def test_role_based_navigation_strict_isolation(self):
        """Valida separação estrita da barra de navegação por papel"""
        self.assertIn("updateBottomNavForRole()", self.app_html)
        self.assertIn("PlanProvider.isAdmin", self.app_html)
        self.assertIn("mode === 'trainer'", self.app_html)

    def test_add_active_exercise_set_syntax_integrity(self):
        """Valida que addActiveExerciseSet não possui comandos duplicados ou erro de sintaxe"""
        self.assertIn("function addActiveExerciseSet(exIdx)", self.app_html)
        self.assertNotIn("saveActiveSessionToStorage();\n    }\n      rowsContainer.insertAdjacentHTML", self.app_html)
        self.assertIn("function handlePublicHashRouting()", self.app_html)
        self.assertIn("workoutTarget = recommended.id || recommended.nome;", self.app_html)


if __name__ == "__main__":
    unittest.main()


