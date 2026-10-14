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

  setUpAll(() async {
    sqfliteFfiInit();
    testDirectory = await Directory.systemTemp.createTemp(
      'seu_treinao_db_test',
    );
    AppDatabase.configureForTesting(
      factory: databaseFactoryFfi,
      databasePath: p.join(testDirectory.path, 'test.db'),
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
    await database.saveRoutine([
      TrainingDay(
        weekday: DateTime.monday,
        workoutId: workoutId,
        workoutName: workout.name,
      ),
    ], split: 'ABC');
    expect(await database.getSetting('training_split'), 'ABC');

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
  });

  test('rejeita dois treinos programados para o mesmo dia', () async {
    await expectLater(
      AppDatabase.instance.saveTrainingDays([
        TrainingDay(weekday: DateTime.tuesday, workoutId: 1),
        TrainingDay(weekday: DateTime.tuesday, workoutId: 2),
      ]),
      throwsArgumentError,
    );
  });
}
