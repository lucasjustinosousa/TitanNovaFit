import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/titannova_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/timer_audio_service.dart';
import 'data/repositories/workout_repository.dart';
import 'data/models/models.dart';
import 'features/auth/auth_screen.dart';
import 'features/dashboard/home_dashboard.dart';
import 'features/workouts/workout_list_screen.dart';
import 'features/exercises/exercise_library_screen.dart';
import 'features/history/history_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/active_session/active_workout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Notificações Locais
  await TimerAudioService.instance.initNotifications();

  // Inicializar Supabase com credenciais do projeto
  await SupabaseService.instance.initialize(
    url: 'https://gplgywrvejefulsjpkax.supabase.co',
    anonKey: 'sb_publishable_em6WHZt2Ol8JZ16fe_Lcyg_ETq_kIPY',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => WorkoutRepository(),
      child: const TitanNovaFitApp(),
    ),
  );
}

class TitanNovaFitApp extends StatelessWidget {
  const TitanNovaFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TitanNova Fit',
      debugShowCheckedModeBanner: false,
      theme: TitanNovaTheme.darkTheme,
      home: const MainRootNavigator(),
    );
  }
}

class MainRootNavigator extends StatefulWidget {
  const MainRootNavigator({super.key});

  @override
  State<MainRootNavigator> createState() => _MainRootNavigatorState();
}

class _MainRootNavigatorState extends State<MainRootNavigator> {
  bool _isAuthenticated = false;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  void _checkInitialAuth() {
    final user = SupabaseService.instance.currentUser;
    if (user != null) {
      _isAuthenticated = true;
    }
  }

  void _startWorkout(Treino treino) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(treino: treino),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return AuthScreen(
        onLoginSuccess: () {
          setState(() {
            _isAuthenticated = true;
          });
        },
      );
    }

    final List<Widget> pages = [
      HomeDashboard(
        onNavigateToTab: (index) => setState(() => _currentTabIndex = index),
        onStartWorkout: _startWorkout,
      ),
      WorkoutListScreen(
        onStartWorkout: _startWorkout,
      ),
      const ExerciseLibraryScreen(modoSelecao: false),
      const HistoryScreen(),
      ProfileScreen(
        onLogout: () async {
          await SupabaseService.instance.signOut();
          if (mounted) {
            await Provider.of<WorkoutRepository>(context, listen: false).definirUsuario(null);
            setState(() {
              _isAuthenticated = false;
              _currentTabIndex = 0;
            });
          }
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarThemeData().selectedItemColor != null
              ? BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início')
              : BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Treinos'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_gymnastics), label: 'Exercícios'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Histórico'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
