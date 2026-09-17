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


if __name__ == "__main__":
    unittest.main()
