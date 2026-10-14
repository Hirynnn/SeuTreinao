import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/database_service.dart';
import 'package:seu_treinao/services/workout_rules.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory testDirectory;
  late String testDatabasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    testDirectory = await Directory.systemTemp.createTemp(
      'seu_treinao_db_test',
    );
    testDatabasePath = p.join(testDirectory.path, 'test.db');
    AppDatabase.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: testDatabasePath,
    );
  });

  tearDownAll(() async {
    await AppDatabase.closeForTesting();
    await testDirectory.delete(recursive: true);
  });

  test('persiste rotina, treino e sessão sem alterar o histórico', () async {
    final database = AppDatabase.instance;
    final catalog = await database.listExercises(query: 'Supino reto');
    expect(catalog, hasLength(1));
    final fullCatalog = await database.listExercises();
    expect(fullCatalog.length, greaterThanOrEqualTo(80));
    expect(
      fullCatalog.map((exercise) => exercise.muscleGroup).toSet(),
      containsAll([
        'Peito',
        'Costas',
        'Ombros',
        'Bíceps',
        'Tríceps',
        'Antebraços',
        'Quadríceps',
        'Posteriores',
        'Glúteos',
        'Panturrilhas',
        'Abdômen',
        'Outros',
      ]),
    );
    final beforeReopenCount = fullCatalog.length;
    await AppDatabase.closeForTesting();
    AppDatabase.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: p.join(testDirectory.path, 'test.db'),
    );
    expect(
      (await AppDatabase.instance.listExercises()).length,
      beforeReopenCount,
      reason: 'O catálogo pré-definido não deve duplicar após abrir novamente.',
    );

    final workout = Workout(
      name: 'Treino A',
      exercises: [
        WorkoutExercise(
          exerciseName: catalog.single.name,
          exerciseId: catalog.single.id,
          orderIndex: 0,
          sets: [
            WorkoutSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
            WorkoutSet(setNumber: 2, plannedWeight: 45, plannedReps: 8),
          ],
        ),
      ],
    );
    final workoutId = await database.saveWorkout(workout);
    final nextWorkoutId = await database.saveWorkout(Workout(name: 'Treino B'));
    await database.saveWorkoutQueue([
      WorkoutQueueEntry(
        position: 1,
        workoutId: workoutId,
        workoutName: workout.name,
      ),
      WorkoutQueueEntry(
        position: 2,
        workoutId: nextWorkoutId,
        workoutName: 'Treino B',
      ),
      WorkoutQueueEntry(
        position: 3,
        workoutId: workoutId,
        workoutName: workout.name,
      ),
    ], split: 'ABC');
    var queue = await database.listWorkoutQueue();
    expect(queue.map((entry) => entry.workoutId), [
      workoutId,
      nextWorkoutId,
      workoutId,
    ]);
    expect(
      await database.getSetting('workout_queue_next_entry_id'),
      '${queue.first.id}',
    );
    expect(await database.getSetting('training_split'), 'ABC');
    expect((await database.getDashboardSnapshot()).nextWorkout?.id, workoutId);

    final session = WorkoutSession(
      workoutId: workoutId,
      workoutName: workout.name,
      startedAt: DateTime(2025, 1, 6, 18),
      status: SessionStatus.inProgress,
      exercises: [
        SessionExercise(
          exerciseName: catalog.single.name,
          muscleGroup: catalog.single.muscleGroup,
          orderIndex: 0,
          sets: [
            SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
            SessionSet(setNumber: 2, plannedWeight: 45, plannedReps: 8),
          ],
        ),
      ],
    );
    await database.saveSession(session);

    final restored = await database.getActiveSession();
    expect(restored, isNotNull);
    expect(restored!.exercises.single.sets, hasLength(2));

    final progress = SessionProgress(session: restored);
    progress.completeCurrentSet(actualWeight: 42.5, actualReps: 10);
    await database.saveSession(progress.session);

    final latest = (await database.listSessions()).single;
    expect(latest.status, SessionStatus.inProgress);
    expect(latest.workoutName, 'Treino A');
    expect(latest.exercises.single.muscleGroup, 'Peito');
    expect(latest.exercises.single.sets.first.completed, isTrue);
    expect(latest.exercises.single.sets.first.actualWeight, 42.5);
    expect(latest.exercises.single.sets.first.completedAt, isNotNull);
    expect(latest.exercises.single.sets.last.completed, isFalse);

    await database.saveWorkout(
      Workout(
        id: workoutId,
        name: 'Treino A editado',
        exercises: [
          WorkoutExercise(
            exerciseName: 'Agachamento atualizado',
            sets: [WorkoutSet(setNumber: 1, plannedWeight: 80, plannedReps: 6)],
          ),
        ],
      ),
    );
    final historical = (await database.listSessions()).single;
    expect(historical.workoutName, 'Treino A');
    expect(historical.exercises.single.exerciseName, 'Supino reto');
    expect(historical.exercises.single.sets.first.actualWeight, 42.5);

    progress.completeCurrentSet(actualWeight: 45, actualReps: 8);
    await database.saveSession(progress.session);
    queue = await database.listWorkoutQueue();
    expect(
      await database.getSetting('workout_queue_next_entry_id'),
      '${queue[1].id}',
    );
    expect(
      (await database.getDashboardSnapshot()).nextWorkout?.id,
      nextWorkoutId,
    );
    await database.saveSession(progress.session);
    expect(
      await database.getSetting('workout_queue_next_entry_id'),
      '${queue[1].id}',
    );

    await database.saveSession(
      WorkoutSession(
        workoutId: nextWorkoutId,
        workoutName: 'Treino B',
        startedAt: DateTime(2025, 1, 7, 18),
        endedAt: DateTime(2025, 1, 7, 19),
        status: SessionStatus.completed,
      ),
    );
    expect(
      await database.getSetting('workout_queue_next_entry_id'),
      '${queue[2].id}',
    );
    await database.saveSession(
      WorkoutSession(
        workoutId: workoutId,
        workoutName: 'Treino A',
        startedAt: DateTime(2025, 1, 8, 18),
        endedAt: DateTime(2025, 1, 8, 19),
        status: SessionStatus.completed,
      ),
    );
    expect(
      await database.getSetting('workout_queue_next_entry_id'),
      '${queue.first.id}',
    );
  });

  test('rejeita adicionar à fila um treino que não existe', () async {
    await expectLater(
      AppDatabase.instance.saveWorkoutQueue([
        WorkoutQueueEntry(
          position: 1,
          workoutId: -1,
          workoutName: 'Treino inexistente',
        ),
      ], split: 'ABC'),
      throwsArgumentError,
    );
  });

  test('migra a rotina semanal existente para uma fila ordenada', () async {
    await AppDatabase.closeForTesting();
    final legacyPath = p.join(testDirectory.path, 'legacy.db');
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE workouts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE training_days (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weekday INTEGER NOT NULL,
              workout_id INTEGER,
              workout_name TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
          ''');
          await db.insert('workouts', {'id': 10, 'name': 'Treino A'});
          await db.insert('workouts', {'id': 30, 'name': 'Treino B'});
          await db.insert('training_days', {
            'weekday': DateTime.friday,
            'workout_id': 30,
            'workout_name': 'Treino B',
          });
          await db.insert('training_days', {
            'weekday': DateTime.monday,
            'workout_id': 10,
            'workout_name': 'Treino A',
          });
          await db.insert('training_days', {
            'weekday': DateTime.wednesday,
            'workout_id': 10,
            'workout_name': 'Treino A',
          });
        },
      ),
    );
    await legacyDatabase.close();

    AppDatabase.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    try {
      final migratedQueue = await AppDatabase.instance.listWorkoutQueue();
      expect(migratedQueue.map((entry) => entry.workoutName), [
        'Treino A',
        'Treino A',
        'Treino B',
      ]);
      expect(migratedQueue.map((entry) => entry.position), [1, 2, 3]);
      expect(
        await AppDatabase.instance.getSetting('workout_queue_next_entry_id'),
        '${migratedQueue.first.id}',
      );
      await AppDatabase.instance.saveWorkoutQueue(migratedQueue, split: 'ABC');
    } finally {
      await AppDatabase.closeForTesting();
      AppDatabase.configureForTesting(
        factory: databaseFactoryFfi,
        databasePath: testDatabasePath,
      );
    }
  });
}
