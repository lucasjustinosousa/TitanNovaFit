import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/models.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('titannova_fit_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgradeDB,
    );
  }

  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE exercicios ADD COLUMN gif_url TEXT;');
      } catch (e) {
        // Coluna já pode existir
      }
    }
    if (oldVersion < 3) {
      // Atualizar gifs nos exercícios padrão existentes
      await _seedExerciseLibrary(db);
    }
  }

  Future _createDB(Database db, int version) async {
    // 1. Tabela Usuarios
    await db.execute('''
      CREATE TABLE usuarios (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        email TEXT NOT NULL,
        foto_url TEXT,
        unidade_carga TEXT DEFAULT 'kg',
        descanso_padrao INTEGER DEFAULT 60,
        criado_em TEXT NOT NULL
      )
    ''');

    // 2. Tabela Exercicios
    await db.execute('''
      CREATE TABLE exercicios (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        grupo_muscular TEXT NOT NULL,
        musculos_auxiliares TEXT,
        equipamento TEXT NOT NULL,
        instrucoes TEXT NOT NULL,
        cuidados TEXT,
        gif_url TEXT,
        video_url TEXT,
        imagem_url TEXT,
        personalizado INTEGER DEFAULT 0,
        usuario_id TEXT,
        is_favorito INTEGER DEFAULT 0
      )
    ''');

    // 3. Tabela Treinos
    await db.execute('''
      CREATE TABLE treinos (
        id TEXT PRIMARY KEY,
        usuario_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        descricao TEXT,
        dias_semana TEXT NOT NULL,
        cor_hex TEXT DEFAULT '#1E88E5',
        criado_em TEXT NOT NULL
      )
    ''');

    // 4. Tabela Exercicios do Treino
    await db.execute('''
      CREATE TABLE exercicios_do_treino (
        id TEXT PRIMARY KEY,
        treino_id TEXT NOT NULL,
        exercicio_id TEXT NOT NULL,
        ordem INTEGER NOT NULL,
        quantidade_series INTEGER DEFAULT 4,
        repeticoes TEXT DEFAULT '10-12',
        carga_inicial REAL DEFAULT 0.0,
        descanso_segundos INTEGER DEFAULT 60,
        observacoes TEXT
      )
    ''');

    // 5. Tabela Sessoes de Treino
    await db.execute('''
      CREATE TABLE sessoes_de_treino (
        id TEXT PRIMARY KEY,
        usuario_id TEXT NOT NULL,
        treino_id TEXT NOT NULL,
        nome_treino TEXT NOT NULL,
        inicio TEXT NOT NULL,
        fim TEXT,
        observacoes TEXT,
        concluido INTEGER DEFAULT 0
      )
    ''');

    // 6. Tabela Series Realizadas
    await db.execute('''
      CREATE TABLE series_realizadas (
        id TEXT PRIMARY KEY,
        sessao_id TEXT NOT NULL,
        exercicio_id TEXT NOT NULL,
        numero_serie INTEGER NOT NULL,
        carga REAL NOT NULL,
        repeticoes INTEGER NOT NULL,
        concluida INTEGER DEFAULT 0
      )
    ''');

    // Popular biblioteca inicial de exercícios padrão em PT-BR
    await _seedExerciseLibrary(db);
  }

  Future<void> _seedExerciseLibrary(Database db) async {
    final seedExercises = [
      // Peito
      Exercicio(
        id: 'base_peito_1',
        nome: 'Supino Reto com Barra',
        grupoMuscular: 'Peito',
        musculosAuxiliares: 'Tríceps, Deltoide Anterior',
        equipamento: 'Barra e Banco Reto',
        instrucoes: 'Deite-se no banco com os olhos alinhados à barra. Segure a barra um pouco além da largura dos ombros. Desça a barra de forma controlada até o meio do peito e empurre estendendo os braços.',
        cuidados: 'Mantenha as escápulas aduzidas e os pés firmes no chão. Evite rebater a barra no peito.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/pectorals/barbell-bench-press.gif',
      ),
      Exercicio(
        id: 'base_peito_2',
        nome: 'Supino Inclinado com Halteres',
        grupoMuscular: 'Peito',
        musculosAuxiliares: 'Tríceps, Deltoide Anterior',
        equipamento: 'Halteres e Banco Inclinado',
        instrucoes: 'Ajuste o banco em ângulo de 30º a 45º. Posicione os halteres acima do peito e desça flexionando os cotovelos até a linha dos ombros.',
        cuidados: 'Não incline demais o banco para não sobrecarregar os ombros.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/pectorals/dumbbell-incline-bench-press.gif',
      ),
      Exercicio(
        id: 'base_peito_3',
        nome: 'Crucifixo no Crossover (Polia Alta)',
        grupoMuscular: 'Peito',
        musculosAuxiliares: 'Deltoide Anterior',
        equipamento: 'Polia / Crossover',
        instrucoes: 'Com os cotovelos levemente flexionados, junte as mãos à frente do quadril controlando o movimento.',
        cuidados: 'Controle a fase concêntrica e excêntrica sem dar trancos.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/pectorals/cable-middle-fly.gif',
      ),
      Exercicio(
        id: 'base_peito_4',
        nome: 'Peck Deck / Voador',
        grupoMuscular: 'Peito',
        musculosAuxiliares: 'Deltoide Anterior',
        equipamento: 'Máquina Voador',
        instrucoes: 'Ajuste o banco na altura do peitoral. Junte os braços à frente contraindo o peito e retorne devagar.',
        cuidados: 'Mantenha as costas firmes no encosto.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/pectorals/cable-cross-over-variation.gif',
      ),
      Exercicio(
        id: 'base_peito_5',
        nome: 'Flexão de Braços',
        grupoMuscular: 'Peito',
        musculosAuxiliares: 'Tríceps, Core',
        equipamento: 'Peso Corporal',
        instrucoes: 'Apoie as mãos no chão na largura dos ombros. Desça o corpo em linha reta e empurre até a posição inicial.',
        cuidados: 'Mantenha o abdômen contraído para não arquear a lombar.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/pectorals/push-up.gif',
      ),

      // Costas
      Exercicio(
        id: 'base_costas_1',
        nome: 'Puxada Frontal na Polia',
        grupoMuscular: 'Costas',
        musculosAuxiliares: 'Bíceps, Antebraço, Trapézio',
        equipamento: 'Polia Alta',
        instrucoes: 'Segure a barra aberta com pegada pronada. Puxe a barra em direção ao peitoral superior estufando o tórax.',
        cuidados: 'Evite inclinar o tronco excessivamente para trás.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/lats/cable-lat-pulldown-full-range-of-motion.gif',
      ),
      Exercicio(
        id: 'base_costas_2',
        nome: 'Remada Curvada com Barra',
        grupoMuscular: 'Costas',
        musculosAuxiliares: 'Bíceps, Eretores da Espinha',
        equipamento: 'Barra',
        instrucoes: 'Incline o tronco a cerca de 45º com costas retas. Puxe a barra em direção ao abdômen.',
        cuidados: 'Mantenha a curvatura natural da coluna durante toda a execução.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/upper-back/barbell-bent-over-row.gif',
      ),
      Exercicio(
        id: 'base_costas_3',
        nome: 'Remada Unilateral com Halter (Serrote)',
        grupoMuscular: 'Costas',
        musculosAuxiliares: 'Bíceps, Deltoide Posterior',
        equipamento: 'Halteres e Banco',
        instrucoes: 'Apoie um joelho e uma mão no banco. Puxe o halter na direção do quadril rente ao tronco.',
        cuidados: 'Evite rotacionar o quadril no final da puxada.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/upper-back/dumbbell-one-arm-bent-over-row.gif',
      ),
      Exercicio(
        id: 'base_costas_4',
        nome: 'Puxada Articulada',
        grupoMuscular: 'Costas',
        musculosAuxiliares: 'Bíceps, Trapézio',
        equipamento: 'Máquina Articulada',
        instrucoes: 'Puxe as manoplas para baixo e para trás aproximando as escápulas.',
        cuidados: 'Retorne alongando bem os dorsais.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/lats/lever-front-pulldown.gif',
      ),
      Exercicio(
        id: 'base_costas_5',
        nome: 'Barra Fixa (Pull-up)',
        grupoMuscular: 'Costas',
        musculosAuxiliares: 'Bíceps, Antebraço',
        equipamento: 'Peso Corporal / Barra Fixa',
        instrucoes: 'Pendure-se na barra com pegada pronada. Puxe o corpo até o queixo ultrapassar a barra.',
        cuidados: 'Desça controlando a velocidade do movimento.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/lats/pull-up.gif',
      ),

      // Pernas
      Exercicio(
        id: 'base_pernas_1',
        nome: 'Agachamento Livre com Barra',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Glúteos, Eretores da Espinha',
        equipamento: 'Barra e Rack',
        instrucoes: 'Apoie a barra sobre o trapézio. Flexione joelhos e quadril até 90º e empurre o chão pelos calcanhares.',
        cuidados: 'Mantenha os joelhos alinhados com as pontas dos pés.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/glutes/barbell-full-squat.gif',
      ),
      Exercicio(
        id: 'base_pernas_2',
        nome: 'Leg Press 45º',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Quadríceps, Glúteos, Isquiotibiais',
        equipamento: 'Máquina Leg Press',
        instrucoes: 'Apoie os pés na plataforma na largura do quadril. Desça até 90º e empurre.',
        cuidados: 'Nunca bloqueie ou hiperestenda os joelhos no topo.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/quads/lever-alternate-leg-press.gif',
      ),
      Exercicio(
        id: 'base_pernas_3',
        nome: 'Cadeira Extensora',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Quadríceps, Reto Femoral',
        equipamento: 'Máquina Extensora',
        instrucoes: 'Estenda as pernas para cima contraindo os quadríceps no topo e desça devagar.',
        cuidados: 'Evite usar impulso exagerado para subir a carga.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/quads/lever-leg-extension.gif',
      ),
      Exercicio(
        id: 'base_pernas_4',
        nome: 'Mesa Flexora',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Isquiotibiais, Glúteos',
        equipamento: 'Máquina Flexora',
        instrucoes: 'Deite-se com o rolo nos tornozelos. Flexione os joelhos puxando em direção aos glúteos.',
        cuidados: 'Não levante o quadril do banco durante a flexão.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/hamstrings/lever-lying-leg-curl.gif',
      ),
      Exercicio(
        id: 'base_pernas_5',
        nome: 'Stiff com Halteres / Barra',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Isquiotibiais, Glúteos, Lombar',
        equipamento: 'Barra / Halteres',
        instrucoes: 'Incline o quadril para trás descendo o peso rente às pernas até sentir os posteriores.',
        cuidados: 'Mantenha a coluna reta e os joelhos destravados.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/glutes/barbell-stiff-leg-deadlift.gif',
      ),
      Exercicio(
        id: 'base_pernas_6',
        nome: 'Elevação de Gêmeos (Panturrilha)',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Gastrocnêmio, Sóleo',
        equipamento: 'Máquina ou Degrau',
        instrucoes: 'Eleve o corpo ao máximo nas pontas dos pés, pause 1s e desça alongando bem.',
        cuidados: 'Mantenha o movimento amplo e controlado.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/calves/barbell-standing-calf-raise.gif',
      ),
      Exercicio(
        id: 'base_pernas_7',
        nome: 'Panturrilha Sentado',
        grupoMuscular: 'Pernas',
        musculosAuxiliares: 'Sóleo, Gastrocnêmio',
        equipamento: 'Máquina Gêmeos Sentado',
        instrucoes: 'Ajuste a almofada sobre as coxas e eleve os calcanhares contraindo a panturrilha.',
        cuidados: 'Faça o movimento completo sem rebater.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/calves/lever-seated-calf-raise.gif',
      ),

      // Ombros
      Exercicio(
        id: 'base_ombros_1',
        nome: 'Desenvolvimento com Halteres',
        grupoMuscular: 'Ombros',
        musculosAuxiliares: 'Tríceps, Trapézio',
        equipamento: 'Halteres e Banco',
        instrucoes: 'Sentado com as costas apoiadas, eleve os halteres acima da cabeça até estender os braços.',
        cuidados: 'Não arqueie as costas nem empurre a cabeça à frente.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/delts/dumbbell-shoulder-press.gif',
      ),
      Exercicio(
        id: 'base_ombros_2',
        nome: 'Elevação Lateral com Halteres',
        grupoMuscular: 'Ombros',
        musculosAuxiliares: 'Deltoide Lateral, Trapézio',
        equipamento: 'Halteres',
        instrucoes: 'Em pé, eleve os halteres lateralmente até a altura dos ombros e desça devagar.',
        cuidados: 'Evite balançar o tronco para levantar a carga.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/delts/dumbbell-lateral-raise.gif',
      ),
      Exercicio(
        id: 'base_ombros_3',
        nome: 'Elevação Frontal',
        grupoMuscular: 'Ombros',
        musculosAuxiliares: 'Deltoide Anterior, Peitoral Superior',
        equipamento: 'Halteres ou Polia',
        instrucoes: 'Segure os halteres à frente e eleve até a altura dos olhos mantendo a postura.',
        cuidados: 'Mantenha o tronco estável durante todo o exercício.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/delts/dumbbell-front-raise-v-2.gif',
      ),
      Exercicio(
        id: 'base_ombros_4',
        nome: 'Crucifixo Invertido',
        grupoMuscular: 'Ombros',
        musculosAuxiliares: 'Deltoide Posterior, Romboides',
        equipamento: 'Halteres ou Peck Deck',
        instrucoes: 'Incline o tronco e abra os braços para trás com foco na parte posterior dos ombros.',
        cuidados: 'Não use impulso excessivo.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/delts/dumbbell-rear-lateral-raise.gif',
      ),
      Exercicio(
        id: 'base_ombros_5',
        nome: 'Encolhimento com Halteres',
        grupoMuscular: 'Ombros',
        musculosAuxiliares: 'Trapézio Superior, Antebraço',
        equipamento: 'Halteres',
        instrucoes: 'Em pé segurando os halteres ao lado do corpo, eleve os ombros em direção às orelhas.',
        cuidados: 'Evite girar os ombros durante o encolhimento.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/upper-back/dumbbell-shrug.gif',
      ),

      // Bíceps
      Exercicio(
        id: 'base_biceps_1',
        nome: 'Rosca Direta com Barra W',
        grupoMuscular: 'Bíceps',
        musculosAuxiliares: 'Braquial, Antebraço',
        equipamento: 'Barra W',
        instrucoes: 'Mantenha os cotovelos fixos ao lado do tronco e flexione os braços trazendo a barra.',
        cuidados: 'Evite inclinar o corpo para trás.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/biceps/barbell-curl.gif',
      ),
      Exercicio(
        id: 'base_biceps_2',
        nome: 'Rosca Martelo com Halteres',
        grupoMuscular: 'Bíceps',
        musculosAuxiliares: 'Braquiorradial, Antebraço',
        equipamento: 'Halteres',
        instrucoes: 'Com pegada neutra (palmas para dentro), eleve os halteres sem girar os punhos.',
        cuidados: 'Controle a velocidade na descida.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/biceps/dumbbell-hammer-curl.gif',
      ),
      Exercicio(
        id: 'base_biceps_3',
        nome: 'Rosca Concentrada',
        grupoMuscular: 'Bíceps',
        musculosAuxiliares: 'Pico do Bíceps, Braquial',
        equipamento: 'Halter e Banco',
        instrucoes: 'Apoie o cotovelo na parte interna da coxa e erga o halter contraindo ao máximo.',
        cuidados: 'Mantenha o braço estável.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/biceps/dumbbell-concentration-curl.gif',
      ),
      Exercicio(
        id: 'base_biceps_4',
        nome: 'Rosca Scott na Polia',
        grupoMuscular: 'Bíceps',
        musculosAuxiliares: 'Bíceps, Braquial',
        equipamento: 'Banco Scott e Polia',
        instrucoes: 'Apoie os braços no banco Scott e flexione os cotovelos isolando os bíceps.',
        cuidados: 'Não estenda os braços bruscamente na descida.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/biceps/barbell-preacher-curl.gif',
      ),

      // Tríceps
      Exercicio(
        id: 'base_triceps_1',
        nome: 'Tríceps Pulley na Corda',
        grupoMuscular: 'Tríceps',
        musculosAuxiliares: 'Antebraço',
        equipamento: 'Polia Alta e Corda',
        instrucoes: 'Empurre a corda para baixo abrindo as pontas no final do movimento para contração máxima.',
        cuidados: 'Mantenha os cotovelos colados ao corpo.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/triceps/cable-rope-pushdown.gif',
      ),
      Exercicio(
        id: 'base_triceps_2',
        nome: 'Tríceps Testa com Barra W',
        grupoMuscular: 'Tríceps',
        musculosAuxiliares: 'Tríceps Cabeça Longa',
        equipamento: 'Barra W e Banco Reto',
        instrucoes: 'Deitado no banco, flexione os cotovelos descendo a barra até a testa e empurre para cima.',
        cuidados: 'Não abra os cotovelos para fora.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/triceps/barbell-lying-triceps-extension.gif',
      ),
      Exercicio(
        id: 'base_triceps_3',
        nome: 'Tríceps Coice com Halter',
        grupoMuscular: 'Tríceps',
        musculosAuxiliares: 'Deltoide Posterior',
        equipamento: 'Halteres e Banco',
        instrucoes: 'Com o cotovelo alto, estenda o antebraço para trás contraindo o tríceps.',
        cuidados: 'Mantenha o braço paralelo ao tronco.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/triceps/dumbbell-kickback.gif',
      ),
      Exercicio(
        id: 'base_triceps_4',
        nome: 'Mergulho no Banco (Dips)',
        grupoMuscular: 'Tríceps',
        musculosAuxiliares: 'Peitoral, Deltoide Anterior',
        equipamento: 'Banco ou Paralelas',
        instrucoes: 'Apoie as mãos na borda do banco, desça o quadril até 90º e empurre para cima.',
        cuidados: 'Mantenha as costas próximas ao banco durante a descida.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/triceps/bench-dip-knees-bent.gif',
      ),

      // Abdômen & Core
      Exercicio(
        id: 'base_abdom_1',
        nome: 'Abdominal Infra no Solo / Elevação de Pernas',
        grupoMuscular: 'Abdômen',
        musculosAuxiliares: 'Flexores do Quadril',
        equipamento: 'Colchonete',
        instrucoes: 'Deitado de costas, eleve as pernas retas até a vertical e desça devagar sem tocar o chão.',
        cuidados: 'Mantenha a lombar apoiada no chão.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/abs/lying-leg-raise.gif',
      ),
      Exercicio(
        id: 'base_abdom_2',
        nome: 'Prancha Ventral Isométrica',
        grupoMuscular: 'Abdômen',
        musculosAuxiliares: 'Lombar, Glúteos, Core',
        equipamento: 'Colchonete',
        instrucoes: 'Apoie os antebraços e pontas dos pés mantendo o corpo em linha reta e abdômen contraído.',
        cuidados: 'Não deixe o quadril descer ou subir demais.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/abs/bodyweight-plank.gif',
      ),
      Exercicio(
        id: 'base_abdom_3',
        nome: 'Abdominal Supra na Polia / Solo',
        grupoMuscular: 'Abdômen',
        musculosAuxiliares: 'Reto Abdominal',
        equipamento: 'Colchonete / Polia',
        instrucoes: 'Flexione o tronco aproximando as costelas do quadril, solte o ar no topo e retorne.',
        cuidados: 'Não puxe o pescoço com as mãos.',
        gifUrl: 'https://cdn.jsdelivr.net/gh/JahelCuadrado/ExerciseGymGifsDB@v1.1.0/abs/crunch.gif',
      ),
    ];

    for (var ex in seedExercises) {
      await db.insert('exercicios', ex.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // Métodos CRUD para Exercícios
  Future<List<Exercicio>> getExercicios() async {
    final db = await instance.database;
    var result = await db.query('exercicios', orderBy: 'nome ASC');
    if (result.isEmpty || result.any((r) => r['id'].toString().startsWith('base_') && (r['gif_url'] == null || r['gif_url'].toString().isEmpty))) {
      await _seedExerciseLibrary(db);
      result = await db.query('exercicios', orderBy: 'nome ASC');
    }
    return result.map((json) => Exercicio.fromMap(json)).toList();
  }

  Future<void> saveExercicio(Exercicio ex) async {
    final db = await instance.database;
    await db.insert('exercicios', ex.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> toggleFavorito(String exercicioId, bool currentFav) async {
    final db = await instance.database;
    await db.update(
      'exercicios',
      {'is_favorito': currentFav ? 0 : 1},
      where: 'id = ?',
      whereArgs: [exercicioId],
    );
  }

  // Métodos CRUD para Treinos com isolamento por usuário
  Future<List<Treino>> getTreinos(String usuarioId) async {
    final db = await instance.database;
    final result = usuarioId.isNotEmpty
        ? await db.query(
            'treinos',
            where: 'usuario_id = ?',
            whereArgs: [usuarioId],
            orderBy: 'criado_em DESC',
          )
        : <Map<String, Object?>>[];
    
    List<Treino> treinos = [];
    for (var row in result) {
      final treinoId = row['id'] as String;
      final exerciciosRows = await db.query(
        'exercicios_do_treino',
        where: 'treino_id = ?',
        whereArgs: [treinoId],
        orderBy: 'ordem ASC',
      );

      List<ExercicioDoTreino> exList = [];
      for (var exRow in exerciciosRows) {
        final exId = exRow['exercicio_id'] as String;
        final exInfoResult = await db.query('exercicios', where: 'id = ?', whereArgs: [exId]);
        Exercicio? exInfo = exInfoResult.isNotEmpty ? Exercicio.fromMap(exInfoResult.first) : null;
        exList.add(ExercicioDoTreino.fromMap(exRow, exercicioInfo: exInfo));
      }

      treinos.add(Treino.fromMap(row, exercicios: exList));
    }

    return treinos;
  }

  Future<void> saveTreino(Treino treino) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert('treinos', treino.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      
      // Deletar anteriores para atualizar a lista
      await txn.delete('exercicios_do_treino', where: 'treino_id = ?', whereArgs: [treino.id]);
      
      for (var ex in treino.exercicios) {
        await txn.insert('exercicios_do_treino', ex.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteTreino(String treinoId) async {
    final db = await instance.database;
    await db.delete('treinos', where: 'id = ?', whereArgs: [treinoId]);
    await db.delete('exercicios_do_treino', where: 'treino_id = ?', whereArgs: [treinoId]);
  }

  // Métodos para Sessão de Treino e Séries Realizadas com isolamento por usuário
  Future<void> salvarSessaoRealizada(SessaoTreino sessao, List<SerieRealizada> series) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert('sessoes_de_treino', sessao.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      for (var serie in series) {
        await txn.insert('series_realizadas', serie.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<SessaoTreino>> getHistoricoSessoes([String? usuarioId]) async {
    final db = await instance.database;
    final result = (usuarioId != null && usuarioId.isNotEmpty)
        ? await db.query(
            'sessoes_de_treino',
            where: 'usuario_id = ?',
            whereArgs: [usuarioId],
            orderBy: 'inicio DESC',
          )
        : await db.query('sessoes_de_treino', orderBy: 'inicio DESC');
    return result.map((json) => SessaoTreino.fromMap(json)).toList();
  }

  Future<List<SerieRealizada>> getSeriesPorSessao(String sessaoId) async {
    final db = await instance.database;
    final result = await db.query('series_realizadas', where: 'sessao_id = ?', whereArgs: [sessaoId]);
    return result.map((json) => SerieRealizada.fromMap(json)).toList();
  }
}
