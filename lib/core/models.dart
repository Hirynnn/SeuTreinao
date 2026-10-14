import 'package:seu_treinao/core/enums.dart';

class Exercise {
  Exercise({
    this.id,
    required this.name,
    this.muscleGroup = 'Outros',
    this.isCustom = false,
  });

  final int? id;
  final String name;
  final String muscleGroup;
  final bool isCustom;

  Exercise copyWith({
    int? id,
    String? name,
    String? muscleGroup,
    bool? isCustom,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      muscleGroup: muscleGroup ?? this.muscleGroup,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'muscle_group': muscleGroup,
      'is_custom': isCustom ? 1 : 0,
    };
  }

  factory Exercise.fromMap(Map<String, Object?> map) {
    return Exercise(
      id: map['id'] as int?,
      name: map['name'] as String? ?? 'Exercício',
      muscleGroup: map['muscle_group'] as String? ?? 'Outros',
      isCustom: (map['is_custom'] as int? ?? 0) == 1,
    );
  }
}

class WorkoutSet {
  WorkoutSet({
    this.id,
    required this.setNumber,
    required this.plannedWeight,
    required this.plannedReps,
    this.actualWeight,
    this.actualReps,
    this.completed = false,
    this.skipped = false,
  });

  final int? id;
  final int setNumber;
  final double plannedWeight;
  final int plannedReps;
  final double? actualWeight;
  final int? actualReps;
  final bool completed;
  final bool skipped;

  WorkoutSet copyWith({
    int? id,
    int? setNumber,
    double? plannedWeight,
    int? plannedReps,
    double? actualWeight,
    int? actualReps,
    bool? completed,
    bool? skipped,
  }) {
    return WorkoutSet(
      id: id ?? this.id,
      setNumber: setNumber ?? this.setNumber,
      plannedWeight: plannedWeight ?? this.plannedWeight,
      plannedReps: plannedReps ?? this.plannedReps,
      actualWeight: actualWeight ?? this.actualWeight,
      actualReps: actualReps ?? this.actualReps,
      completed: completed ?? this.completed,
      skipped: skipped ?? this.skipped,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'set_number': setNumber,
      'planned_weight': plannedWeight,
      'planned_reps': plannedReps,
      'actual_weight': actualWeight,
      'actual_reps': actualReps,
      'completed': completed ? 1 : 0,
      'skipped': skipped ? 1 : 0,
    };
  }
}

class WorkoutExercise {
  WorkoutExercise({
    this.id,
    required this.exerciseName,
    this.exerciseId,
    this.orderIndex = 0,
    required this.sets,
  });

  final int? id;
  final String exerciseName;
  final int? exerciseId;
  final int orderIndex;
  final List<WorkoutSet> sets;

  WorkoutExercise copyWith({
    int? id,
    String? exerciseName,
    int? exerciseId,
    int? orderIndex,
    List<WorkoutSet>? sets,
  }) {
    return WorkoutExercise(
      id: id ?? this.id,
      exerciseName: exerciseName ?? this.exerciseName,
      exerciseId: exerciseId ?? this.exerciseId,
      orderIndex: orderIndex ?? this.orderIndex,
      sets: sets ?? this.sets,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'exercise_name': exerciseName,
      'exercise_id': exerciseId,
      'order_index': orderIndex,
      'sets': sets.map((s) => s.toMap()).toList(),
    };
  }
}

class Workout {
  Workout({
    this.id,
    required this.name,
    this.description,
    List<WorkoutExercise>? exercises,
  }) : exercises = exercises ?? <WorkoutExercise>[];

  final int? id;
  final String name;
  final String? description;
  final List<WorkoutExercise> exercises;

  Workout copyWith({
    int? id,
    String? name,
    String? description,
    List<WorkoutExercise>? exercises,
  }) {
    return Workout(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      exercises: exercises ?? this.exercises,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'exercises': exercises.map((e) => e.toMap()).toList(),
    };
  }
}

class WorkoutQueueEntry {
  WorkoutQueueEntry({
    this.id,
    required this.position,
    required this.workoutId,
    required this.workoutName,
  });

  final int? id;
  final int position;
  final int workoutId;
  final String workoutName;
}

class WorkoutSession {
  WorkoutSession({
    this.id,
    required this.workoutId,
    required this.workoutName,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.currentExerciseIndex = 0,
    this.currentSetIndex = 0,
    List<SessionExercise>? exercises,
  }) : exercises = exercises ?? <SessionExercise>[];

  final int? id;
  final int workoutId;
  final String workoutName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;
  final int currentExerciseIndex;
  final int currentSetIndex;
  final List<SessionExercise> exercises;

  WorkoutSession copyWith({
    int? id,
    int? workoutId,
    String? workoutName,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
    SessionStatus? status,
    int? currentExerciseIndex,
    int? currentSetIndex,
    List<SessionExercise>? exercises,
  }) {
    return WorkoutSession(
      id: id ?? this.id,
      workoutId: workoutId ?? this.workoutId,
      workoutName: workoutName ?? this.workoutName,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      status: status ?? this.status,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      currentSetIndex: currentSetIndex ?? this.currentSetIndex,
      exercises: exercises ?? this.exercises,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'workout_id': workoutId,
      'workout_name': workoutName,
      'started_at': startedAt.millisecondsSinceEpoch,
      'ended_at': endedAt?.millisecondsSinceEpoch,
      'status': status.name,
      'current_exercise_index': currentExerciseIndex,
      'current_set_index': currentSetIndex,
      'exercises': exercises.map((e) => e.toMap()).toList(),
    };
  }
}

class SessionExercise {
  SessionExercise({
    this.id,
    required this.exerciseName,
    this.muscleGroup = 'Outros',
    required this.orderIndex,
    required this.sets,
  });

  final int? id;
  final String exerciseName;
  final String muscleGroup;
  final int orderIndex;
  final List<SessionSet> sets;

  SessionExercise copyWith({
    int? id,
    String? exerciseName,
    String? muscleGroup,
    int? orderIndex,
    List<SessionSet>? sets,
  }) {
    return SessionExercise(
      id: id ?? this.id,
      exerciseName: exerciseName ?? this.exerciseName,
      muscleGroup: muscleGroup ?? this.muscleGroup,
      orderIndex: orderIndex ?? this.orderIndex,
      sets: sets ?? this.sets,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'exercise_name': exerciseName,
      'muscle_group': muscleGroup,
      'order_index': orderIndex,
      'sets': sets.map((s) => s.toMap()).toList(),
    };
  }
}

class SessionSet {
  SessionSet({
    this.id,
    required this.setNumber,
    required this.plannedWeight,
    required this.plannedReps,
    this.actualWeight,
    this.actualReps,
    this.completedAt,
    this.completed = false,
    this.skipped = false,
  });

  final int? id;
  final int setNumber;
  final double plannedWeight;
  final int plannedReps;
  final double? actualWeight;
  final int? actualReps;
  final DateTime? completedAt;
  final bool completed;
  final bool skipped;

  SessionSet copyWith({
    int? id,
    int? setNumber,
    double? plannedWeight,
    int? plannedReps,
    double? actualWeight,
    int? actualReps,
    DateTime? completedAt,
    bool? completed,
    bool? skipped,
  }) {
    return SessionSet(
      id: id ?? this.id,
      setNumber: setNumber ?? this.setNumber,
      plannedWeight: plannedWeight ?? this.plannedWeight,
      plannedReps: plannedReps ?? this.plannedReps,
      actualWeight: actualWeight ?? this.actualWeight,
      actualReps: actualReps ?? this.actualReps,
      completedAt: completedAt ?? this.completedAt,
      completed: completed ?? this.completed,
      skipped: skipped ?? this.skipped,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'set_number': setNumber,
      'planned_weight': plannedWeight,
      'planned_reps': plannedReps,
      'actual_weight': actualWeight,
      'actual_reps': actualReps,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'completed': completed ? 1 : 0,
      'skipped': skipped ? 1 : 0,
    };
  }
}

class DashboardSnapshot {
  DashboardSnapshot({
    required this.date,
    required this.nextWorkout,
    required this.queueLength,
    required this.lastCompletedSession,
    required this.hasActiveSession,
  });

  final DateTime date;
  final Workout? nextWorkout;
  final int queueLength;
  final WorkoutSession? lastCompletedSession;
  final bool hasActiveSession;
}
