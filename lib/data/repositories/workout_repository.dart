import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../../core/database/local_database.dart';
import '../../core/services/supabase_service.dart';

class WorkoutRepository extends ChangeNotifier {
  final _uuid = const Uuid();
  Usuario? _usuarioAtual;
  List<Treino> _treinos = [];
  List<Exercicio> _exercicios = [];
  List<SessaoTreino> _historico = [];
  bool _isLoading = false;

  Usuario? get usuarioAtual => _usuarioAtual;
  List<Treino> get treinos => _treinos;
  List<Exercicio> get exercicios => _exercicios;
  List<SessaoTreino> get historico => _historico;
  bool get isLoading => _isLoading;

  WorkoutRepository() {
    _initDefaults();
  }

  Future<void> _initDefaults() async {
    _isLoading = true;
    notifyListeners();

    // Se houver usuário autenticado no Supabase, inicializar com a sessão ativa
    final authUser = SupabaseService.instance.currentUser;
    if (authUser != null) {
      final email = authUser.email ?? '';
      final meta = authUser.userMetadata ?? {};
      final nome = (meta['nome'] as String?) ?? (email.isNotEmpty ? email.split('@')[0] : 'Atleta TitanNova');
      _usuarioAtual = Usuario(
        id: authUser.id,
        nome: nome,
        email: email,
        unidadeCarga: 'kg',
        descansoPadrao: 60,
        criadoEm: DateTime.now(),
      );
    } else {
      _usuarioAtual = null;
    }

    await carregarDados();
    _isLoading = false;
    notifyListeners();
  }

  /// Define o usuário ativo e recarrega os dados locais isolados
  Future<void> definirUsuario(Usuario? user) async {
    _usuarioAtual = user;
    _isLoading = true;
    notifyListeners();
    await carregarDados();
    _isLoading = false;
    notifyListeners();
  }

  /// Define o usuário ativo a partir de um objeto de autenticação do Supabase
  Future<void> definirUsuarioAutenticado(dynamic authUser) async {
    if (authUser == null) {
      await definirUsuario(null);
      return;
    }
    final email = (authUser.email as String?) ?? '';
    final meta = (authUser.userMetadata as Map<String, dynamic>?) ?? {};
    final nome = (meta['nome'] as String?) ?? (email.isNotEmpty ? email.split('@')[0] : 'Atleta TitanNova');
    final usuario = Usuario(
      id: authUser.id as String,
      nome: nome,
      email: email,
      unidadeCarga: 'kg',
      descansoPadrao: 60,
      criadoEm: DateTime.now(),
    );
    await definirUsuario(usuario);
  }

  Future<void> carregarDados() async {
    try {
      // 1. Carregar exercícios da biblioteca local
      _exercicios = await LocalDatabase.instance.getExercicios();

      // Se nenhum usuário autenticado ou convidado ativo, limpar treinos e histórico
      if (_usuarioAtual == null) {
        _treinos = [];
        _historico = [];
        notifyListeners();
        return;
      }

      final uid = _usuarioAtual!.id;

      // 2. Carregar treinos locais do SQLite filtrados estritamente pelo usuarioAtual
      _treinos = await LocalDatabase.instance.getTreinos(uid);
      _historico = await LocalDatabase.instance.getHistoricoSessoes(uid);

      // 3. Se nenhum treino cadastrado ainda localmente para este usuário, gerar treinos padrão
      if (_treinos.isEmpty && _exercicios.isNotEmpty) {
        await _seedDefaultTreinos();
        _treinos = await LocalDatabase.instance.getTreinos(uid);
      }

      // 4. Sincronização Bidirecional completa com a Nuvem (Supabase)
      if (SupabaseService.instance.isInitialized && SupabaseService.instance.currentUser != null) {
        final treinosOnline = await SupabaseService.instance.fetchTreinosOnline();
        
        // A) Salvar no SQLite qualquer treino que esteja na nuvem e não no SQLite
        final localIds = _treinos.map((t) => t.id).toSet();
        for (var t in treinosOnline) {
          if (!localIds.contains(t.id)) {
            await LocalDatabase.instance.saveTreino(t);
          }
        }

        // B) Enviar para a nuvem qualquer treino do SQLite que ainda não esteja na nuvem
        final onlineIds = treinosOnline.map((t) => t.id).toSet();
        for (var t in _treinos) {
          if (!onlineIds.contains(t.id)) {
            await SupabaseService.instance.syncTreino(t);
          }
        }

        // Recarregar lista consolidada de treinos isolados do usuário
        _treinos = await LocalDatabase.instance.getTreinos(uid);
      }
    } catch (e) {
      debugPrint('Erro ao carregar e sincronizar dados: $e');
    }
    notifyListeners();
  }

  Future<void> _seedDefaultTreinos() async {
    if (_usuarioAtual == null) return;
    final uid = _usuarioAtual!.id;

    final peito = _exercicios.firstWhere((e) => e.grupoMuscular == 'Peito', orElse: () => _exercicios.first);
    final triceps = _exercicios.firstWhere((e) => e.grupoMuscular == 'Tríceps', orElse: () => _exercicios.first);
    final costas = _exercicios.firstWhere((e) => e.grupoMuscular == 'Costas', orElse: () => _exercicios.first);
    final biceps = _exercicios.firstWhere((e) => e.grupoMuscular == 'Bíceps', orElse: () => _exercicios.first);
    final pernas = _exercicios.firstWhere((e) => e.grupoMuscular == 'Pernas', orElse: () => _exercicios.first);

    final treinoA = Treino(
      id: 'treino_${uid}_a',
      usuarioId: uid,
      nome: 'Treino A — Peito & Tríceps',
      descricao: 'Hipertrofia',
      diasSemana: ['Segunda-feira', 'Quinta-feira'],
      corHex: '#1E88E5',
      criadoEm: DateTime.now(),
      exercicios: [
        ExercicioDoTreino(id: 'ex_${uid}_a1', treinoId: 'treino_${uid}_a', exercicioId: peito.id, ordem: 1, quantidadeSeries: 4, repeticoes: '10-12', cargaInicial: 30, descansoSegundos: 90, exercicioInfo: peito),
        ExercicioDoTreino(id: 'ex_${uid}_a2', treinoId: 'treino_${uid}_a', exercicioId: triceps.id, ordem: 2, quantidadeSeries: 3, repeticoes: '12-15', cargaInicial: 20, descansoSegundos: 60, exercicioInfo: triceps),
      ],
    );

    final treinoB = Treino(
      id: 'treino_${uid}_b',
      usuarioId: uid,
      nome: 'Treino B — Costas & Bíceps',
      descricao: 'Hipertrofia',
      diasSemana: ['Terça-feira', 'Sexta-feira'],
      corHex: '#00D2FF',
      criadoEm: DateTime.now(),
      exercicios: [
        ExercicioDoTreino(id: 'ex_${uid}_b1', treinoId: 'treino_${uid}_b', exercicioId: costas.id, ordem: 1, quantidadeSeries: 4, repeticoes: '10-12', cargaInicial: 40, descansoSegundos: 90, exercicioInfo: costas),
        ExercicioDoTreino(id: 'ex_${uid}_b2', treinoId: 'treino_${uid}_b', exercicioId: biceps.id, ordem: 2, quantidadeSeries: 3, repeticoes: '10-12', cargaInicial: 12, descansoSegundos: 60, exercicioInfo: biceps),
      ],
    );

    final ombros = _exercicios.firstWhere((e) => e.grupoMuscular == 'Ombros', orElse: () => _exercicios.first);
    final abdomen = _exercicios.firstWhere((e) => e.grupoMuscular == 'Abdômen', orElse: () => _exercicios.first);

    final treinoC = Treino(
      id: 'treino_${uid}_c',
      usuarioId: uid,
      nome: 'Treino C — Pernas & Panturrilhas',
      descricao: 'Força & Resistência',
      diasSemana: ['Quarta-feira', 'Sábado'],
      corHex: '#4CAF50',
      criadoEm: DateTime.now(),
      exercicios: [
        ExercicioDoTreino(id: 'ex_${uid}_c1', treinoId: 'treino_${uid}_c', exercicioId: pernas.id, ordem: 1, quantidadeSeries: 4, repeticoes: '8-10', cargaInicial: 60, descansoSegundos: 120, exercicioInfo: pernas),
      ],
    );

    final treinoD = Treino(
      id: 'treino_${uid}_d',
      usuarioId: uid,
      nome: 'Treino D — Ombros, Trapézio & Abdômen',
      descricao: 'Definição & Core',
      diasSemana: ['Sexta-feira'],
      corHex: '#FF9800',
      criadoEm: DateTime.now(),
      exercicios: [
        ExercicioDoTreino(id: 'ex_${uid}_d1', treinoId: 'treino_${uid}_d', exercicioId: ombros.id, ordem: 1, quantidadeSeries: 4, repeticoes: '10-12', cargaInicial: 16, descansoSegundos: 60, exercicioInfo: ombros),
        ExercicioDoTreino(id: 'ex_${uid}_d2', treinoId: 'treino_${uid}_d', exercicioId: abdomen.id, ordem: 2, quantidadeSeries: 3, repeticoes: '15-20', cargaInicial: 0, descansoSegundos: 45, exercicioInfo: abdomen),
      ],
    );

    await LocalDatabase.instance.saveTreino(treinoA);
    await LocalDatabase.instance.saveTreino(treinoB);
    await LocalDatabase.instance.saveTreino(treinoC);
    await LocalDatabase.instance.saveTreino(treinoD);

    if (SupabaseService.instance.isInitialized && SupabaseService.instance.currentUser != null) {
      await SupabaseService.instance.syncTreino(treinoA);
      await SupabaseService.instance.syncTreino(treinoB);
      await SupabaseService.instance.syncTreino(treinoC);
      await SupabaseService.instance.syncTreino(treinoD);
    }
  }

  // Operações de Treinos
  Future<void> salvarTreino(Treino treino) async {
    await LocalDatabase.instance.saveTreino(treino);
    await SupabaseService.instance.syncTreino(treino);
    await carregarDados();
  }

  Future<void> duplicarTreino(Treino treino) async {
    final novoTreino = Treino(
      id: _uuid.v4(),
      usuarioId: treino.usuarioId,
      nome: '${treino.nome} (Cópia)',
      descricao: treino.descricao,
      diasSemana: treino.diasSemana,
      corHex: treino.corHex,
      criadoEm: DateTime.now(),
      exercicios: treino.exercicios.map((e) => ExercicioDoTreino(
        id: _uuid.v4(),
        treinoId: '',
        exercicioId: e.exercicioId,
        ordem: e.ordem,
        quantidadeSeries: e.quantidadeSeries,
        repeticoes: e.repeticoes,
        cargaInicial: e.cargaInicial,
        descansoSegundos: e.descansoSegundos,
        observacoes: e.observacoes,
        exercicioInfo: e.exercicioInfo,
      )).toList(),
    );

    await salvarTreino(novoTreino);
  }

  Future<void> deletarTreino(String treinoId) async {
    await LocalDatabase.instance.deleteTreino(treinoId);
    await SupabaseService.instance.deleteTreinoOnline(treinoId);
    await carregarDados();
  }

  // Operações de Exercícios
  Future<void> salvarExercicioCustomizado(Exercicio ex) async {
    await LocalDatabase.instance.saveExercicio(ex);
    await carregarDados();
  }

  Future<void> toggleFavorito(String exercicioId) async {
    final ex = _exercicios.firstWhere((e) => e.id == exercicioId);
    await LocalDatabase.instance.toggleFavorito(exercicioId, ex.isFavorito);
    await carregarDados();
  }

  // Finalização do Treino
  Future<void> finalizarSessao(SessaoTreino sessao, List<SerieRealizada> series) async {
    await LocalDatabase.instance.salvarSessaoRealizada(sessao, series);
    await SupabaseService.instance.syncSessao(sessao, series);
    await carregarDados();
  }

  // Configurações do Usuário
  void atualizarUnidade(String unidade) {
    if (_usuarioAtual != null) {
      _usuarioAtual = Usuario(
        id: _usuarioAtual!.id,
        nome: _usuarioAtual!.nome,
        email: _usuarioAtual!.email,
        fotoUrl: _usuarioAtual!.fotoUrl,
        unidadeCarga: unidade,
        descansoPadrao: _usuarioAtual!.descansoPadrao,
        criadoEm: _usuarioAtual!.criadoEm,
      );
      notifyListeners();
    }
  }

  void atualizarDescansoPadrao(int segundos) {
    if (_usuarioAtual != null) {
      _usuarioAtual = Usuario(
        id: _usuarioAtual!.id,
        nome: _usuarioAtual!.nome,
        email: _usuarioAtual!.email,
        fotoUrl: _usuarioAtual!.fotoUrl,
        unidadeCarga: _usuarioAtual!.unidadeCarga,
        descansoPadrao: segundos,
        criadoEm: _usuarioAtual!.criadoEm,
      );
      notifyListeners();
    }
  }
}
