import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/titannova_theme.dart';
import '../common/disclaimer_banner.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/services/supabase_service.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha o e-mail e a senha.'),
          backgroundColor: TitanNovaTheme.errorRed,
        ),
      );
      return;
    }

    if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, insira um endereço de e-mail válido.'),
          backgroundColor: TitanNovaTheme.warningOrange,
        ),
      );
      return;
    }

    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha deve conter no mínimo 6 caracteres.'),
          backgroundColor: TitanNovaTheme.warningOrange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (SupabaseService.instance.isInitialized) {
        if (_isLogin) {
          final user = await SupabaseService.instance.signIn(email, pass);
          if (user != null) {
            if (mounted) {
              await Provider.of<WorkoutRepository>(context, listen: false).definirUsuarioAutenticado(user);
              setState(() => _isLoading = false);
              widget.onLoginSuccess();
            }
            return;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Credenciais incorretas ou usuário não encontrado.'),
                  backgroundColor: TitanNovaTheme.errorRed,
                ),
              );
            }
          }
        } else {
          final user = await SupabaseService.instance.signUp(email, pass);
          if (user != null) {
            if (mounted) {
              await Provider.of<WorkoutRepository>(context, listen: false).definirUsuarioAutenticado(user);
              setState(() => _isLoading = false);
              widget.onLoginSuccess();
            }
            return;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cadastro recebido! Se a confirmação estiver ativada, verifique sua caixa de entrada.'),
                  backgroundColor: TitanNovaTheme.successGreen,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Serviço de autenticação offline. Use a opção "Modo Convidado" abaixo.'),
              backgroundColor: TitanNovaTheme.warningOrange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Auth] Falha na autenticação: $e');
      if (mounted) {
        final errText = e.toString().replaceAll('Exception:', '').replaceAll('AuthException:', '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha: $errText'),
            backgroundColor: TitanNovaTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _continueAsGuest() {
    final guestUser = Usuario(
      id: 'guest_user_1',
      nome: 'Atleta Convidado',
      email: 'convidado@titannovafit.com',
      unidadeCarga: 'kg',
      descansoPadrao: 60,
      criadoEm: DateTime.now(),
    );
    Provider.of<WorkoutRepository>(context, listen: false).definirUsuario(guestUser);
    widget.onLoginSuccess();
  }

  void _recuperarSenha() {
    final recoverController = TextEditingController(text: _emailController.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TitanNovaTheme.cardDark,
        title: const Text('Recuperar Senha', style: TextStyle(color: TitanNovaTheme.textWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Digite seu e-mail cadastrado para receber o link oficial de redefinição de senha:',
              style: TextStyle(color: TitanNovaTheme.textGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: recoverController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: TitanNovaTheme.textWhite),
              decoration: const InputDecoration(labelText: 'E-mail cadastrado'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: TitanNovaTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = recoverController.text.trim();
              if (email.isEmpty || !RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, insira um e-mail válido.'),
                    backgroundColor: TitanNovaTheme.warningOrange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                if (SupabaseService.instance.isInitialized) {
                  await SupabaseService.instance.resetPassword(email);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Se o e-mail estiver cadastrado, as instruções foram enviadas!'),
                      backgroundColor: TitanNovaTheme.successGreen,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao enviar recuperação: $e'),
                      backgroundColor: TitanNovaTheme.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAlignment.center,
            children: [
              const SizedBox(height: 30),
              // LOGOTIPO TITANNOVA FIT
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: TitanNovaTheme.primaryBlue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: TitanNovaTheme.primaryBlue.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  size: 52,
                  color: TitanNovaTheme.textWhite,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'TITANNOVA ',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.black,
                        color: TitanNovaTheme.textWhite,
                        letterSpacing: 1.5,
                      ),
                    ),
                    TextSpan(
                      text: 'FIT',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.black,
                        color: TitanNovaTheme.accentCyan,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Seu Treino sob Controle Absoluto',
                style: TextStyle(color: TitanNovaTheme.textGrey, fontSize: 14),
              ),
              const SizedBox(height: 36),

              // Formulário de Autenticação
              TextField(
                controller: _emailController,
                style: const TextStyle(color: TitanNovaTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.email_outlined, color: TitanNovaTheme.primaryBlue),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passController,
                obscureText: true,
                style: const TextStyle(color: TitanNovaTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: Icon(Icons.lock_outline, color: TitanNovaTheme.primaryBlue),
                ),
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _recuperarSenha,
                  child: const Text(
                    'Esqueceu a senha?',
                    style: TextStyle(color: TitanNovaTheme.accentCyan, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Botões Principais
              ElevatedButton(
                onPressed: _isLoading ? null : _submitAuth,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isLogin ? 'ENTRAR' : 'CRIAR MINHA CONTA'),
              ),
              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() => _isLogin = !_isLogin);
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: TitanNovaTheme.primaryBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _isLogin ? 'Criar nova conta' : 'Já possuo uma conta (Entrar)',
                  style: const TextStyle(color: TitanNovaTheme.primaryBlue, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),

              // Botão Continuar Sem Cadastro (Modo Convidado Explícito)
              TextButton(
                onPressed: _isLoading ? null : _continueAsGuest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Continuar sem cadastro (Modo Convidado)',
                      style: TextStyle(color: TitanNovaTheme.textGrey, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 12, color: TitanNovaTheme.textGrey),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              // BANNER DE SEGURANÇA E SAÚDE OBRIGATÓRIO
              const DisclaimerBanner(compact: false),
            ],
          ),
        ),
      ),
    );
  }
}
