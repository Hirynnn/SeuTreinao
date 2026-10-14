import 'package:flutter_test/flutter_test.dart';
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/statistics_service.dart';
import 'package:seu_treinao/services/workout_rules.dart';

void main() {
  group('WorkoutQueueRules', () {
    final queue = <WorkoutQueueEntry>[
      WorkoutQueueEntry(
        id: 11,
        position: 1,
        workoutId: 1,
        workoutName: 'Treino A',
      ),
      WorkoutQueueEntry(
        id: 12,
        position: 2,
        workoutId: 2,
        workoutName: 'Treino B',
      ),
      WorkoutQueueEntry(
        id: 13,
        position: 3,
        workoutId: 1,
        workoutName: 'Treino A',
      ),
    ];

    test('começa pelo primeiro item se ainda não há posição salva', () {
      expect(WorkoutQueueRules.getNextEntry(queue)?.id, 11);
    });

    test('recupera a próxima posição salva da fila', () {
      expect(
        WorkoutQueueRules.getNextEntry(queue, nextEntryId: 12)?.workoutId,
        2,
      );
    });

    test('distingue ocorrências repetidas do mesmo treino', () {
      expect(WorkoutQueueRules.getNextEntry(queue, nextEntryId: 13)?.id, 13);
    });

    test('posição removida recomeça no primeiro treino válido', () {
      expect(WorkoutQueueRules.getNextEntry(queue, nextEntryId: 99)?.id, 11);
    });

    test('fila vazia não tem próximo treino', () {
      expect(WorkoutQueueRules.getNextEntry([]), isNull);
    });
  });

  group('SessionProgress', () {
    test('concluir uma série avança para a próxima série', () {
      final session = WorkoutSession(
        workoutId: 1,
        workoutName: 'Treino A',
        startedAt: DateTime.now(),
        status: SessionStatus.inProgress,
        exercises: [
          SessionExercise(
            exerciseName: 'Supino',
            orderIndex: 0,
            sets: [
              SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
              SessionSet(setNumber: 2, plannedWeight: 45, plannedReps: 8),
            ],
          ),
        ],
      );

      final progress = SessionProgress(session: session);
      progress.completeCurrentSet();

      expect(progress.session.currentSetIndex, 1);
      expect(progress.session.exercises.first.sets.first.completed, isTrue);
      expect(
        progress.session.exercises.first.sets.first.completedAt,
        isNotNull,
      );
      expect(progress.session.status, SessionStatus.inProgress);
    });

    test(
      'voltar à série anterior mantém o resultado e permite corrigir a carga',
      () {
        final progress = SessionProgress(
          session: WorkoutSession(
            workoutId: 1,
            workoutName: 'Treino A',
            startedAt: DateTime.now(),
            status: SessionStatus.inProgress,
            exercises: [
              SessionExercise(
                exerciseName: 'Supino',
                orderIndex: 0,
                sets: [
                  SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
                  SessionSet(setNumber: 2, plannedWeight: 45, plannedReps: 8),
                ],
              ),
            ],
          ),
        );

        progress.completeCurrentSet(actualWeight: 42, actualReps: 10);
        progress.goToPreviousSet();

        expect(progress.currentSet.actualWeight, 42);
        expect(progress.currentSet.completed, isTrue);
        progress.completeCurrentSet(actualWeight: 43, actualReps: 9);
        expect(progress.session.exercises.first.sets.first.actualWeight, 43);
        expect(
          progress.session.exercises.first.sets
              .where((set) => set.completed)
              .length,
          1,
        );
      },
    );

    test(
      'pular série registra como pulada sem contabilizá-la como concluída',
      () {
        final progress = SessionProgress(
          session: WorkoutSession(
            workoutId: 1,
            workoutName: 'Treino A',
            startedAt: DateTime.now(),
            status: SessionStatus.inProgress,
            exercises: [
              SessionExercise(
                exerciseName: 'Supino',
                orderIndex: 0,
                sets: [
                  SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
                  SessionSet(setNumber: 2, plannedWeight: 45, plannedReps: 8),
                ],
              ),
            ],
          ),
        );

        progress.skipCurrentSet();

        expect(progress.session.exercises.first.sets.first.skipped, isTrue);
        expect(progress.session.exercises.first.sets.first.completed, isFalse);
        expect(progress.session.status, SessionStatus.inProgress);
        expect(progress.currentSetIndex, 1);
      },
    );

    test('finalizar com séries pendentes salva uma sessão incompleta', () {
      final progress = SessionProgress(
        session: WorkoutSession(
          workoutId: 1,
          workoutName: 'Treino A',
          startedAt: DateTime.now(),
          status: SessionStatus.inProgress,
          exercises: [
            SessionExercise(
              exerciseName: 'Supino',
              orderIndex: 0,
              sets: [
                SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
              ],
            ),
          ],
        ),
      );

      progress.finalizeIncomplete();

      expect(progress.session.status, SessionStatus.incomplete);
      expect(progress.session.endedAt, isNotNull);
      expect(progress.session.exercises.first.sets.first.completed, isFalse);
    });

    test('a sessão finaliza como concluída quando todas as séries forem completadas', () {
      final session = WorkoutSession(
        workoutId: 1,
        workoutName: 'Treino A',
        startedAt: DateTime.now(),
        status: SessionStatus.inProgress,
        exercises: [
          SessionExercise(
            exerciseName: 'Supino',
            orderIndex: 0,
            sets: [
              SessionSet(setNumber: 1, plannedWeight: 40, plannedReps: 10),
            ],
          ),
        ],
      );

      final progress = SessionProgress(session: session);
      progress.completeCurrentSet();

      expect(progress.session.status, SessionStatus.completed);
      expect(progress.session.endedAt, isNotNull);
    });
  });

  group('TrainingStatistics', () {
    test('calcula métricas com sessões incompletas e ignora canceladas', () {
      final sessions = [
        WorkoutSession(
          workoutId: 1,
          workoutName: 'Cancelado',
          startedAt: DateTime(2025, 1, 3, 8),
          endedAt: DateTime(2025, 1, 3, 9),
          status: SessionStatus.cancelled,
          exercises: [
            SessionExercise(
              exerciseName: 'Supino',
              muscleGroup: 'Peito',
              orderIndex: 0,
              sets: [
                SessionSet(
                  setNumber: 1,
                  plannedWeight: 100,
                  plannedReps: 1,
                  actualWeight: 200,
                  actualReps: 1,
                  completed: true,
                ),
              ],
            ),
          ],
        ),
        WorkoutSession(
          workoutId: 1,
          workoutName: 'Incompleto',
          startedAt: DateTime(2025, 1, 2, 0, 10),
          endedAt: DateTime(2025, 1, 2, 0, 20),
          status: SessionStatus.incomplete,
          exercises: [
            SessionExercise(
              exerciseName: 'Supino',
              muscleGroup: 'Peito',
              orderIndex: 0,
              sets: [
                SessionSet(
                  setNumber: 1,
                  plannedWeight: 70,
                  plannedReps: 8,
                  actualWeight: 70,
                  actualReps: 8,
                  completed: true,
                ),
              ],
            ),
          ],
        ),
        WorkoutSession(
          workoutId: 1,
          workoutName: 'Concluído',
          startedAt: DateTime(2025, 1, 1, 18),
          endedAt: DateTime(2025, 1, 1, 19),
          status: SessionStatus.completed,
          exercises: [
            SessionExercise(
              exerciseName: 'Supino',
              muscleGroup: 'Peito',
              orderIndex: 0,
              sets: [
                SessionSet(
                  setNumber: 1,
                  plannedWeight: 100,
                  plannedReps: 5,
                  actualWeight: 100,
                  actualReps: 5,
                  completed: true,
                ),
              ],
            ),
          ],
        ),
      ];

      final stats = calculateTrainingStatistics(
        sessions,
        now: DateTime(2025, 1, 14),
      );

      expect(stats.completedSessions, 1);
      expect(stats.incompleteSessions, 1);
      expect(stats.trainedDays, 2);
      expect(stats.averageDurationMinutes, 60);
      expect(stats.exerciseSetCounts['Supino'], 2);
      expect(stats.exerciseLastWeights['Supino'], 70);
      expect(stats.exerciseMaxWeights['Supino'], 100);
      expect(stats.muscleGroupSetCounts['Peito'], 2);
    });

    test('não mostra médias sem sessões concluídas', () {
      final stats = calculateTrainingStatistics([
        WorkoutSession(
          workoutId: 1,
          workoutName: 'Cancelado',
          startedAt: DateTime(2025, 1, 1),
          status: SessionStatus.cancelled,
        ),
      ], now: DateTime(2025, 1, 8));

      expect(stats.averageSessionsPerWeek, isNull);
      expect(stats.averageDurationMinutes, isNull);
      expect(stats.averageStartMinute, isNull);
      expect(stats.completedSessions, 0);
      expect(stats.incompleteSessions, 0);
    });
  });
}
