import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/workout_rules.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static Database? _database;
  static DatabaseFactory? _databaseFactoryOverride;
  static String? _databasePathOverride;

  static void configureForTesting({
    required DatabaseFactory factory,
    required String databasePath,
  }) {
    _databaseFactoryOverride = factory;
    _databasePathOverride = databasePath;
  }

  static Future<void> closeForTesting() async {
    final current = _database;
    if (current != null) {
      await current.close();
      _database = null;
    }
    _databaseFactoryOverride = null;
    _databasePathOverride = null;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath =
        _databasePathOverride ??
        p.join(await getDatabasesPath(), 'seu_treinao.db');
    final factory = _databaseFactoryOverride ?? databaseFactory;

    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDb,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE session_exercises ADD COLUMN muscle_group TEXT NOT NULL DEFAULT 'Outros'",
            );
            await db.execute(
              'ALTER TABLE session_sets ADD COLUMN completed_at INTEGER',
            );
          }
          await _createDb(db, newVersion);
          if (oldVersion < 4) {
            final oldDays = await db.query(
              'training_days',
              orderBy: 'weekday ASC',
            );
            var position = 1;
            int? firstEntryId;
            for (final day in oldDays) {
              final workoutId = day['workout_id'];
              if (workoutId is! int) continue;
              final entryId = await db.insert('workout_queue', {
                'position': position++,
                'workout_id': workoutId,
                'workout_name': day['workout_name'] ?? 'Treino',
              });
              firstEntryId ??= entryId;
            }
            if (firstEntryId != null) {
              await db.insert('app_settings', {
                'key': 'workout_queue_next_entry_id',
                'value': '$firstEntryId',
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await db.execute('DROP TABLE IF EXISTS training_days');
          }
        },
        onOpen: (db) async {
          await _seedExerciseCatalog(db);
        },
      ),
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        muscle_group TEXT NOT NULL DEFAULT 'Outros',
        is_custom INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        exercise_id INTEGER,
        exercise_name TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_exercise_id INTEGER NOT NULL,
        set_number INTEGER NOT NULL,
        planned_weight REAL NOT NULL,
        planned_reps INTEGER NOT NULL,
        actual_weight REAL,
        actual_reps INTEGER,
        completed INTEGER NOT NULL DEFAULT 0,
        skipped INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (workout_exercise_id) REFERENCES workout_exercises(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        position INTEGER NOT NULL UNIQUE,
        workout_id INTEGER NOT NULL,
        workout_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workout_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        workout_name TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        status TEXT NOT NULL,
        current_exercise_index INTEGER NOT NULL DEFAULT 0,
        current_set_index INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        exercise_name TEXT NOT NULL,
        muscle_group TEXT NOT NULL DEFAULT 'Outros',
        order_index INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_exercise_id INTEGER NOT NULL,
        set_number INTEGER NOT NULL,
        planned_weight REAL NOT NULL,
        planned_reps INTEGER NOT NULL,
        actual_weight REAL,
        actual_reps INTEGER,
        completed_at INTEGER,
        completed INTEGER NOT NULL DEFAULT 0,
        skipped INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_exercise_id) REFERENCES session_exercises(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await _seedExerciseCatalog(db);
  }

  Future<void> _seedExerciseCatalog(DatabaseExecutor db) async {
    const catalog = <(String, String)>[
      ('Supino reto', 'Peito'),
      ('Supino inclinado', 'Peito'),
      ('Supino declinado', 'Peito'),
      ('Supino com halteres', 'Peito'),
      ('Supino inclinado com halteres', 'Peito'),
      ('Crucifixo máquina', 'Peito'),
      ('Crucifixo com halteres', 'Peito'),
      ('Crossover na polia', 'Peito'),
      ('Flexão de braços', 'Peito'),
      ('Mergulho nas paralelas', 'Peito'),
      ('Remada curvada', 'Costas'),
      ('Remada unilateral com halter', 'Costas'),
      ('Remada cavalinho', 'Costas'),
      ('Barra fixa', 'Costas'),
      ('Barra fixa supinada', 'Costas'),
      ('Pulldown com braços estendidos', 'Costas'),
      ('Puxada na máquina', 'Costas'),
      ('Puxada frontal aberta', 'Costas'),
      ('Puxada frontal fechada', 'Costas'),
      ('Remada baixa', 'Costas'),
      ('Remada articulada', 'Costas'),
      ('Levantamento terra', 'Costas'),
      ('Encolhimento com halteres', 'Costas'),
      ('Desenvolvimento', 'Ombros'),
      ('Desenvolvimento com halteres', 'Ombros'),
      ('Desenvolvimento Arnold', 'Ombros'),
      ('Elevação lateral', 'Ombros'),
      ('Elevação lateral na polia', 'Ombros'),
      ('Elevação frontal', 'Ombros'),
      ('Crucifixo inverso', 'Ombros'),
      ('Face pull', 'Ombros'),
      ('Remada alta', 'Ombros'),
      ('Rosca direta', 'Bíceps'),
      ('Rosca direta com halteres', 'Bíceps'),
      ('Rosca Scott', 'Bíceps'),
      ('Rosca concentrada', 'Bíceps'),
      ('Rosca martelo', 'Bíceps'),
      ('Rosca alternada', 'Bíceps'),
      ('Rosca na polia', 'Bíceps'),
      ('Rosca inversa', 'Antebraços'),
      ('Flexão de punho', 'Antebraços'),
      ('Extensão de punho', 'Antebraços'),
      ('Farmer walk', 'Antebraços'),
      ('Tríceps corda', 'Tríceps'),
      ('Tríceps pulley barra', 'Tríceps'),
      ('Tríceps testa', 'Tríceps'),
      ('Tríceps francês', 'Tríceps'),
      ('Tríceps coice', 'Tríceps'),
      ('Mergulho no banco', 'Tríceps'),
      ('Agachamento', 'Quadríceps'),
      ('Agachamento frontal', 'Quadríceps'),
      ('Agachamento goblet', 'Quadríceps'),
      ('Agachamento no Smith', 'Quadríceps'),
      ('Leg press', 'Quadríceps'),
      ('Leg press unilateral', 'Quadríceps'),
      ('Cadeira extensora', 'Quadríceps'),
      ('Afundo', 'Quadríceps'),
      ('Avanço caminhando', 'Quadríceps'),
      ('Agachamento búlgaro', 'Quadríceps'),
      ('Hack squat', 'Quadríceps'),
      ('Mesa flexora', 'Posteriores'),
      ('Cadeira flexora', 'Posteriores'),
      ('Stiff com barra', 'Posteriores'),
      ('Stiff com halteres', 'Posteriores'),
      ('Levantamento terra romeno', 'Posteriores'),
      ('Flexora em pé', 'Posteriores'),
      ('Elevação pélvica', 'Glúteos'),
      ('Elevação pélvica unilateral', 'Glúteos'),
      ('Coice na polia', 'Glúteos'),
      ('Abdução de quadril na máquina', 'Glúteos'),
      ('Abdução de quadril na polia', 'Glúteos'),
      ('Extensão de quadril', 'Glúteos'),
      ('Panturrilha em pé', 'Panturrilhas'),
      ('Panturrilha sentado', 'Panturrilhas'),
      ('Panturrilha no leg press', 'Panturrilhas'),
      ('Panturrilha unilateral', 'Panturrilhas'),
      ('Abdominal', 'Abdômen'),
      ('Abdominal bicicleta', 'Abdômen'),
      ('Abdominal na polia', 'Abdômen'),
      ('Elevação de pernas', 'Abdômen'),
      ('Prancha', 'Abdômen'),
      ('Prancha lateral', 'Abdômen'),
      ('Russian twist', 'Abdômen'),
      ('Abdominal infra', 'Abdômen'),
      ('Extensão lombar', 'Costas'),
      ('Good morning', 'Posteriores'),
      ('Corda naval', 'Outros'),
      ('Burpee', 'Outros'),
      ('Polichinelo', 'Outros'),
      ('Alongamento dinâmico', 'Outros'),
    ];
    final existingRows = await db.rawQuery(
      'SELECT LOWER(TRIM(name)) AS name FROM exercises',
    );
    final existingNames = existingRows
        .map((row) => row['name'] as String)
        .toSet();
    final batch = db.batch();
    var missingCount = 0;
    for (final (name, group) in catalog) {
      if (existingNames.add(name.trim().toLowerCase())) {
        batch.insert('exercises', {'name': name, 'muscle_group': group});
        missingCount++;
      }
    }
    if (missingCount > 0) {
      await batch.commit(noResult: true);
    }
  }

  Future<List<Exercise>> listExercises({
    String? query,
    String? muscleGroup,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('LOWER(name) LIKE ?');
      args.add('%${query.toLowerCase()}%');
    }
    if (muscleGroup != null && muscleGroup.isNotEmpty) {
      where.add('muscle_group = ?');
      args.add(muscleGroup);
    }

    final sql =
        'SELECT * FROM exercises${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY name';
    final rows = await db.rawQuery(sql, args);
    return rows.map((row) => Exercise.fromMap(row)).toList();
  }

  Future<void> insertExercise(Exercise exercise) async {
    final db = await database;
    await db.insert('exercises', {
      'name': exercise.name.trim(),
      'muscle_group': exercise.muscleGroup,
      'is_custom': exercise.isCustom ? 1 : 0,
    });
  }

  Future<void> updateExercise(Exercise exercise) async {
    final db = await database;
    if (exercise.id == null) {
      throw ArgumentError('Exercise id is required for update.');
    }
    await db.update(
      'exercises',
      {
        'name': exercise.name.trim(),
        'muscle_group': exercise.muscleGroup,
        'is_custom': exercise.isCustom ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [exercise.id],
    );
  }

  Future<void> deleteExercise(int id) async {
    final db = await database;
    final references = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM workout_exercises WHERE exercise_id = ?',
        [id],
      ),
    );
    if ((references ?? 0) > 0) {
      throw StateError(
        'Este exercício está associado a um treino e não pode ser excluído.',
      );
    }
    await db.delete('exercises', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isExerciseUsed(int id) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM workout_exercises WHERE exercise_id = ?',
        [id],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<List<Workout>> listWorkouts() async {
    final db = await database;
    final workouts = await db.query('workouts', orderBy: 'name');
    final result = <Workout>[];
    for (final workout in workouts) {
      final exerciseRows = await db.query(
        'workout_exercises',
        where: 'workout_id = ?',
        whereArgs: [workout['id']],
        orderBy: 'order_index ASC',
      );
      final exercises = <WorkoutExercise>[];
      for (final exerciseRow in exerciseRows) {
        final setRows = await db.query(
          'workout_sets',
          where: 'workout_exercise_id = ?',
          whereArgs: [exerciseRow['id']],
          orderBy: 'set_number ASC',
        );
        exercises.add(
          WorkoutExercise(
            id: exerciseRow['id'] as int?,
            exerciseName:
                (exerciseRow['exercise_name'] as String?) ?? 'Exercício',
            exerciseId: exerciseRow['exercise_id'] as int?,
            orderIndex: (exerciseRow['order_index'] as int?) ?? 0,
            sets: setRows
                .map(
                  (setRow) => WorkoutSet(
                    id: setRow['id'] as int?,
                    setNumber: (setRow['set_number'] as int?) ?? 1,
                    plannedWeight:
                        (setRow['planned_weight'] as num?)?.toDouble() ?? 0.0,
                    plannedReps: (setRow['planned_reps'] as int?) ?? 0,
                    actualWeight: (setRow['actual_weight'] as num?)?.toDouble(),
                    actualReps: setRow['actual_reps'] as int?,
                    completed: (setRow['completed'] as int?) == 1,
                    skipped: (setRow['skipped'] as int?) == 1,
                  ),
                )
                .toList(),
          ),
        );
      }
      result.add(
        Workout(
          id: workout['id'] as int?,
          name: workout['name'] as String,
          description: workout['description'] as String?,
          exercises: exercises,
        ),
      );
    }
    return result;
  }

  Future<int> saveWorkout(Workout workout) async {
    final db = await database;
    return db.transaction((txn) async {
      final workoutId = workout.id == null
          ? await txn.insert('workouts', {
              'name': workout.name.trim(),
              'description': workout.description?.trim(),
            })
          : workout.id!;
      if (workout.id != null) {
        await txn.update(
          'workouts',
          {
            'name': workout.name.trim(),
            'description': workout.description?.trim(),
          },
          where: 'id = ?',
          whereArgs: [workoutId],
        );
        await txn.delete(
          'workout_exercises',
          where: 'workout_id = ?',
          whereArgs: [workoutId],
        );
      }

      for (var index = 0; index < workout.exercises.length; index++) {
        final exercise = workout.exercises[index];
        final workoutExerciseId = await txn.insert('workout_exercises', {
          'workout_id': workoutId,
          'exercise_id': exercise.exerciseId,
          'exercise_name': exercise.exerciseName,
          'order_index': index,
        });
        for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
          final set = exercise.sets[setIndex];
          await txn.insert('workout_sets', {
            'workout_exercise_id': workoutExerciseId,
            'set_number': setIndex + 1,
            'planned_weight': set.plannedWeight,
            'planned_reps': set.plannedReps,
          });
        }
      }
      return workoutId;
    });
  }

  Future<void> deleteWorkout(int id) async {
    final db = await database;
    final queued = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM workout_queue WHERE workout_id = ?',
        [id],
      ),
    );
    if ((queued ?? 0) > 0) {
      throw StateError('Remova este treino da fila antes de excluí-lo.');
    }
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WorkoutQueueEntry>> listWorkoutQueue() async {
    final db = await database;
    final rows = await db.query('workout_queue', orderBy: 'position ASC');
    return rows
        .map(
          (row) => WorkoutQueueEntry(
            id: row['id'] as int?,
            position: (row['position'] as int?) ?? 1,
            workoutId: row['workout_id'] as int,
            workoutName: row['workout_name'] as String,
          ),
        )
        .toList();
  }

  Future<void> saveWorkoutQueue(
    List<WorkoutQueueEntry> queue, {
    required String split,
  }) async {
    final db = await database;
    final workouts = await listWorkouts();
    final workoutsById = {for (final workout in workouts) workout.id!: workout};
    if (queue.any((entry) => !workoutsById.containsKey(entry.workoutId))) {
      throw ArgumentError('A fila contém um treino que não existe.');
    }
    await db.transaction((txn) async {
      final oldRows = await txn.query('workout_queue', columns: ['id']);
      final oldIds = oldRows.map((row) => row['id'] as int).toSet();
      final retainedIds = queue
          .map((entry) => entry.id)
          .whereType<int>()
          .toSet();
      final providedIds = queue
          .map((entry) => entry.id)
          .whereType<int>()
          .length;
      if (retainedIds.length != providedIds) {
        throw ArgumentError('A fila contém uma posição repetida.');
      }
      if (retainedIds.any((id) => !oldIds.contains(id))) {
        throw ArgumentError('A fila contém uma posição inválida.');
      }

      final pointerRows = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['workout_queue_next_entry_id'],
      );
      final currentPointerId = pointerRows.isEmpty
          ? null
          : int.tryParse(pointerRows.first['value'] as String? ?? '');

      await txn.rawUpdate('UPDATE workout_queue SET position = -position');
      if (retainedIds.isEmpty) {
        await txn.delete('workout_queue');
      } else {
        final placeholders = List.filled(retainedIds.length, '?').join(', ');
        await txn.delete(
          'workout_queue',
          where: 'id NOT IN ($placeholders)',
          whereArgs: retainedIds.toList(),
        );
      }

      int? firstEntryId;
      var currentPointerStillQueued = false;
      for (var index = 0; index < queue.length; index++) {
        final entry = queue[index];
        final workout = workoutsById[entry.workoutId]!;
        final values = {
          'position': index + 1,
          'workout_id': workout.id,
          'workout_name': workout.name,
        };
        final entryId = entry.id;
        if (entryId == null) {
          final insertedId = await txn.insert('workout_queue', values);
          firstEntryId ??= insertedId;
        } else {
          await txn.update(
            'workout_queue',
            values,
            where: 'id = ?',
            whereArgs: [entryId],
          );
          firstEntryId ??= entryId;
          if (entryId == currentPointerId) currentPointerStillQueued = true;
        }
      }

      if (queue.isEmpty) {
        await txn.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['workout_queue_next_entry_id'],
        );
      } else {
        final nextEntryId = currentPointerStillQueued
            ? currentPointerId
            : firstEntryId;
        await txn.insert('app_settings', {
          'key': 'workout_queue_next_entry_id',
          'value': '$nextEntryId',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('app_settings', {
        'key': 'training_split',
        'value': split,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveSession(WorkoutSession session) async {
    final db = await database;
    await db.transaction((txn) async {
      var wasCompleted = false;
      if (session.id == null) {
        final id = await txn.insert('workout_sessions', {
          'workout_id': session.workoutId,
          'workout_name': session.workoutName,
          'started_at': session.startedAt.millisecondsSinceEpoch,
          'ended_at': session.endedAt?.millisecondsSinceEpoch,
          'status': session.status.name,
          'current_exercise_index': session.currentExerciseIndex,
          'current_set_index': session.currentSetIndex,
        });
        for (
          var exerciseIndex = 0;
          exerciseIndex < session.exercises.length;
          exerciseIndex++
        ) {
          final exercise = session.exercises[exerciseIndex];
          final exerciseId = await txn.insert('session_exercises', {
            'session_id': id,
            'exercise_name': exercise.exerciseName,
            'muscle_group': exercise.muscleGroup,
            'order_index': exerciseIndex,
          });
          for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
            final set = exercise.sets[setIndex];
            await txn.insert('session_sets', {
              'session_exercise_id': exerciseId,
              'set_number': setIndex + 1,
              'planned_weight': set.plannedWeight,
              'planned_reps': set.plannedReps,
              'actual_weight': set.actualWeight,
              'actual_reps': set.actualReps,
              'completed_at': set.completedAt?.millisecondsSinceEpoch,
              'completed': set.completed ? 1 : 0,
              'skipped': set.skipped ? 1 : 0,
            });
          }
        }
      } else {
        final existingRows = await txn.query(
          'workout_sessions',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [session.id],
        );
        wasCompleted =
            existingRows.isNotEmpty &&
            existingRows.first['status'] == SessionStatus.completed.name;
        await txn.update(
          'workout_sessions',
          {
            'workout_id': session.workoutId,
            'workout_name': session.workoutName,
            'started_at': session.startedAt.millisecondsSinceEpoch,
            'ended_at': session.endedAt?.millisecondsSinceEpoch,
            'status': session.status.name,
            'current_exercise_index': session.currentExerciseIndex,
            'current_set_index': session.currentSetIndex,
          },
          where: 'id = ?',
          whereArgs: [session.id],
        );
        await txn.delete(
          'session_exercises',
          where: 'session_id = ?',
          whereArgs: [session.id],
        );
        for (
          var exerciseIndex = 0;
          exerciseIndex < session.exercises.length;
          exerciseIndex++
        ) {
          final exercise = session.exercises[exerciseIndex];
          final exerciseId = await txn.insert('session_exercises', {
            'session_id': session.id,
            'exercise_name': exercise.exerciseName,
            'muscle_group': exercise.muscleGroup,
            'order_index': exerciseIndex,
          });
          for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
            final set = exercise.sets[setIndex];
            await txn.insert('session_sets', {
              'session_exercise_id': exerciseId,
              'set_number': setIndex + 1,
              'planned_weight': set.plannedWeight,
              'planned_reps': set.plannedReps,
              'actual_weight': set.actualWeight,
              'actual_reps': set.actualReps,
              'completed_at': set.completedAt?.millisecondsSinceEpoch,
              'completed': set.completed ? 1 : 0,
              'skipped': set.skipped ? 1 : 0,
            });
          }
        }
      }
      if (session.status == SessionStatus.completed && !wasCompleted) {
        await _advanceWorkoutQueue(txn, session.workoutId);
      }
    });
  }

  Future<void> _advanceWorkoutQueue(
    DatabaseExecutor txn,
    int completedWorkoutId,
  ) async {
    final queue = await txn.query('workout_queue', orderBy: 'position ASC');
    if (queue.isEmpty) return;

    final pointerRows = await txn.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['workout_queue_next_entry_id'],
    );
    final pointerId = pointerRows.isEmpty
        ? null
        : int.tryParse(pointerRows.first['value'] as String? ?? '');
    final startIndex = queue.indexWhere((entry) => entry['id'] == pointerId);
    final start = startIndex < 0 ? 0 : startIndex;

    for (var offset = 0; offset < queue.length; offset++) {
      final index = (start + offset) % queue.length;
      if (queue[index]['workout_id'] != completedWorkoutId) continue;
      final nextEntry = queue[(index + 1) % queue.length];
      await txn.insert('app_settings', {
        'key': 'workout_queue_next_entry_id',
        'value': '${nextEntry['id']}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
  }

  Future<List<WorkoutSession>> listSessions() async {
    final db = await database;
    final sessionRows = await db.query(
      'workout_sessions',
      orderBy: 'started_at DESC',
    );
    final sessions = <WorkoutSession>[];
    for (final row in sessionRows) {
      final sessionId = row['id'] as int;
      final exerciseRows = await db.query(
        'session_exercises',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'order_index ASC',
      );
      final exercises = <SessionExercise>[];
      for (final exerciseRow in exerciseRows) {
        final setRows = await db.query(
          'session_sets',
          where: 'session_exercise_id = ?',
          whereArgs: [exerciseRow['id']],
          orderBy: 'set_number ASC',
        );
        exercises.add(
          SessionExercise(
            id: exerciseRow['id'] as int?,
            exerciseName:
                (exerciseRow['exercise_name'] as String?) ?? 'Exercício',
            muscleGroup: (exerciseRow['muscle_group'] as String?) ?? 'Outros',
            orderIndex: (exerciseRow['order_index'] as int?) ?? 0,
            sets: setRows
                .map(
                  (setRow) => SessionSet(
                    id: setRow['id'] as int?,
                    setNumber: (setRow['set_number'] as int?) ?? 1,
                    plannedWeight:
                        (setRow['planned_weight'] as num?)?.toDouble() ?? 0.0,
                    plannedReps: (setRow['planned_reps'] as int?) ?? 0,
                    actualWeight: (setRow['actual_weight'] as num?)?.toDouble(),
                    actualReps: setRow['actual_reps'] as int?,
                    completedAt: setRow['completed_at'] == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(
                            setRow['completed_at'] as int,
                          ),
                    completed: (setRow['completed'] as int?) == 1,
                    skipped: (setRow['skipped'] as int?) == 1,
                  ),
                )
                .toList(),
          ),
        );
      }
      final sessionStatus = SessionStatus.values.firstWhere(
        (status) => status.name == row['status'],
        orElse: () => SessionStatus.inProgress,
      );

      sessions.add(
        WorkoutSession(
          id: sessionId,
          workoutId: (row['workout_id'] as int?) ?? 0,
          workoutName: row['workout_name'] as String? ?? 'Treino',
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['started_at'] as int?) ?? 0,
          ),
          endedAt: row['ended_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(row['ended_at'] as int)
              : null,
          status: sessionStatus,
          currentExerciseIndex: (row['current_exercise_index'] as int?) ?? 0,
          currentSetIndex: (row['current_set_index'] as int?) ?? 0,
          exercises: exercises,
        ),
      );
    }
    return sessions;
  }

  Future<WorkoutSession?> getActiveSession() async {
    final session = (await listSessions()).firstWhere(
      (entry) => entry.status == SessionStatus.inProgress,
      orElse: () => WorkoutSession(
        workoutId: 0,
        workoutName: '',
        startedAt: DateTime.now(),
        status: SessionStatus.completed,
      ),
    );
    return session.status == SessionStatus.inProgress ? session : null;
  }

  Future<DashboardSnapshot> getDashboardSnapshot() async {
    final date = DateTime.now();
    final workouts = await listWorkouts();
    final queue = await listWorkoutQueue();
    final sessions = await listSessions();
    WorkoutSession? latestSession;
    for (final session in sessions) {
      if (session.status == SessionStatus.completed) {
        latestSession = session;
        break;
      }
    }
    final nextEntryId = int.tryParse(
      await getSetting('workout_queue_next_entry_id') ?? '',
    );
    final nextEntry = WorkoutQueueRules.getNextEntry(
      queue,
      nextEntryId: nextEntryId,
    );
    Workout? nextWorkout;
    if (nextEntry != null) {
      for (final workout in workouts) {
        if (workout.id == nextEntry.workoutId) {
          nextWorkout = workout;
          break;
        }
      }
    }
    final activeSession = await getActiveSession();

    return DashboardSnapshot(
      date: date,
      nextWorkout: nextWorkout,
      queueLength: queue.length,
      lastCompletedSession: latestSession,
      hasActiveSession: activeSession != null,
    );
  }
}
