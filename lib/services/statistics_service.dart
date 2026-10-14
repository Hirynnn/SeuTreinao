import 'dart:math' as math;

import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';

class TrainingStatistics {
  const TrainingStatistics({
    required this.completedSessions,
    required this.incompleteSessions,
    required this.trainedDays,
    required this.averageSessionsPerWeek,
    required this.averageDurationMinutes,
    required this.averageStartMinute,
    required this.exerciseSetCounts,
    required this.exerciseLastWeights,
    required this.exerciseMaxWeights,
    required this.muscleGroupSetCounts,
  });

  final int completedSessions;
  final int incompleteSessions;
  final int trainedDays;
  final double? averageSessionsPerWeek;
  final double? averageDurationMinutes;
  final int? averageStartMinute;
  final Map<String, int> exerciseSetCounts;
  final Map<String, double> exerciseLastWeights;
  final Map<String, double> exerciseMaxWeights;
  final Map<String, int> muscleGroupSetCounts;
}

TrainingStatistics calculateTrainingStatistics(
  List<WorkoutSession> sessions, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final included =
      sessions
          .where((session) => session.status != SessionStatus.cancelled)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final completed = included
      .where((session) => session.status == SessionStatus.completed)
      .toList();
  final incomplete = included
      .where((session) => session.status == SessionStatus.incomplete)
      .toList();
  final trainedDates = <DateTime>{};
  final exerciseSetCounts = <String, int>{};
  final exerciseLastWeights = <String, double>{};
  final exerciseMaxWeights = <String, double>{};
  final muscleGroupSetCounts = <String, int>{};

  for (final session in included) {
    for (final exercise in session.exercises) {
      for (final set in exercise.sets.where((item) => item.completed)) {
        trainedDates.add(
          DateTime(
            session.startedAt.year,
            session.startedAt.month,
            session.startedAt.day,
          ),
        );
        exerciseSetCounts.update(
          exercise.exerciseName,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        muscleGroupSetCounts.update(
          exercise.muscleGroup,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        final weight = set.actualWeight;
        if (weight != null) {
          exerciseLastWeights.putIfAbsent(exercise.exerciseName, () => weight);
          final previousMaximum = exerciseMaxWeights[exercise.exerciseName];
          if (previousMaximum == null || weight > previousMaximum) {
            exerciseMaxWeights[exercise.exerciseName] = weight;
          }
        }
      }
    }
  }

  final durations = completed
      .where((session) => session.endedAt != null)
      .map(
        (session) => session.endedAt!.difference(session.startedAt).inMinutes,
      )
      .toList();
  final averageDuration = durations.isEmpty
      ? null
      : durations.reduce((a, b) => a + b) / durations.length;

  final startMinutes = completed
      .map((session) => session.startedAt.hour * 60 + session.startedAt.minute)
      .toList();
  final averageStart = startMinutes.isEmpty
      ? null
      : _circularAverage(startMinutes);

  final averagePerWeek = completed.isEmpty || included.isEmpty
      ? null
      : completed.length /
            math.max(
              1,
              (currentTime.difference(included.last.startedAt).inDays / 7)
                  .ceil(),
            );

  return TrainingStatistics(
    completedSessions: completed.length,
    incompleteSessions: incomplete.length,
    trainedDays: trainedDates.length,
    averageSessionsPerWeek: averagePerWeek,
    averageDurationMinutes: averageDuration,
    averageStartMinute: averageStart,
    exerciseSetCounts: exerciseSetCounts,
    exerciseLastWeights: exerciseLastWeights,
    exerciseMaxWeights: exerciseMaxWeights,
    muscleGroupSetCounts: muscleGroupSetCounts,
  );
}

int _circularAverage(List<int> minutes) {
  var x = 0.0;
  var y = 0.0;
  for (final minute in minutes) {
    final angle = minute * 2 * math.pi / (24 * 60);
    x += math.cos(angle);
    y += math.sin(angle);
  }
  var averageAngle = math.atan2(y, x);
  if (averageAngle < 0) averageAngle += 2 * math.pi;
  return (averageAngle * (24 * 60) / (2 * math.pi)).round() % (24 * 60);
}
