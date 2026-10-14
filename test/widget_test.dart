import 'package:flutter_test/flutter_test.dart';
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/statistics_service.dart';
import 'package:seu_treinao/services/workout_rules.dart';

void main() {
  group('WeeklyWorkoutRules', () {
    final schedule = <TrainingDay>[
      TrainingDay(
        weekday: DateTime.monday,
        workoutId: 1,
        workoutName: 'Treino A',
      ),
      TrainingDay(
        weekday: DateTime.wednesday,
        workoutId: 2,
        workoutName: 'Treino B',
      ),
      TrainingDay(
        weekday: DateTime.friday,
        workoutId: 3,
        workoutName: 'Treino C',
      ),
    ];

    test('a mesma rotina não é deslocada quando um dia é perdido', () {
      final nextDate = WeeklyWorkoutRules.getNextWorkoutDate(
        DateTime(2025, 1, 6),
        schedule,
      );
      expect(nextDate, DateTime(2025, 1, 8));
    });

    test('dias sem treino devem ser considerados descanso', () {
      final status = WeeklyWorkoutRules.evaluateDayStatus(
        DateTime(2025, 1, 7),
        schedule,
      );
      expect(status, DayStatus.rest);
    });

    test('dias agendados ainda não concluídos ficam pendentes', () {
      final status = WeeklyWorkoutRules.evaluateDayStatus(
        DateTime(2025, 1, 6),
        schedule,
      );
      expect(status, DayStatus.pending);
    });

    test('hoje programado pode ser iniciado sem avançar a sequência', () {
      final today = WeeklyWorkoutRules.getWorkoutForDate(
        DateTime(2025, 1, 6),
        schedule,
      );
      final next = WeeklyWorkoutRules.getNextWorkoutDate(
        DateTime(2025, 1, 6),
        schedule,
      );

      expect(today?.workoutName, 'Treino A');
      expect(next, DateTime(2025, 1, 8));
    });

    test('dia de treino incompleto mantém status distinto de concluído', () {
      final status = WeeklyWorkoutRules.evaluateDayStatus(
        DateTime(2025, 1, 6),
        schedule,
        workoutIncomplete: true,
      );

      expect(status, DayStatus.incomplete);
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
