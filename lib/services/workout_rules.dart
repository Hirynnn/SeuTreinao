import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';

class WorkoutQueueRules {
  static WorkoutQueueEntry? getNextEntry(
    List<WorkoutQueueEntry> queue, {
    int? nextEntryId,
  }) {
    if (queue.isEmpty) return null;
    return queue.firstWhere(
      (entry) => entry.id == nextEntryId,
      orElse: () => queue.first,
    );
  }
}

class SessionProgress {
  SessionProgress({required this.session})
    : currentExerciseIndex = session.currentExerciseIndex,
      currentSetIndex = session.currentSetIndex;

  WorkoutSession session;
  int currentExerciseIndex;
  int currentSetIndex;

  SessionExercise get currentExercise =>
      session.exercises[currentExerciseIndex];

  SessionSet get currentSet => currentExercise.sets[currentSetIndex];

  bool get isFinished => session.status != SessionStatus.inProgress;

  void updateCurrentSetResults({required double weight, required int reps}) {
    final exercise = session.exercises[currentExerciseIndex];
    final set = exercise.sets[currentSetIndex];
    final updatedSets = [...exercise.sets];
    updatedSets[currentSetIndex] = set.copyWith(
      actualWeight: weight,
      actualReps: reps,
    );
    final updatedExercises = [...session.exercises];
    updatedExercises[currentExerciseIndex] = exercise.copyWith(
      sets: updatedSets,
    );
    session = session.copyWith(exercises: updatedExercises);
  }

  bool get canGoToPreviousSet {
    if (currentSetIndex > 0) {
      return true;
    }
    return currentExerciseIndex > 0;
  }

  void goToPreviousSet() {
    if (!canGoToPreviousSet) return;
    if (currentSetIndex > 0) {
      currentSetIndex--;
    } else {
      currentExerciseIndex--;
      currentSetIndex = session.exercises[currentExerciseIndex].sets.length - 1;
    }
    session = session.copyWith(
      currentExerciseIndex: currentExerciseIndex,
      currentSetIndex: currentSetIndex,
    );
  }

  void completeCurrentSet({double? actualWeight, int? actualReps}) {
    final exercise = session.exercises[currentExerciseIndex];
    final existingSet = exercise.sets[currentSetIndex];

    final updatedSet = existingSet.copyWith(
      actualWeight:
          actualWeight ?? existingSet.actualWeight ?? existingSet.plannedWeight,
      actualReps:
          actualReps ?? existingSet.actualReps ?? existingSet.plannedReps,
      completedAt: DateTime.now(),
      completed: true,
      skipped: false,
    );

    final updatedExerciseSets = [...exercise.sets];
    updatedExerciseSets[currentSetIndex] = updatedSet;

    final updatedExercise = exercise.copyWith(sets: updatedExerciseSets);
    final updatedExercises = [...session.exercises];
    updatedExercises[currentExerciseIndex] = updatedExercise;

    final hasMoreSets = currentSetIndex + 1 < updatedExercise.sets.length;
    final hasMoreExercises = currentExerciseIndex + 1 < updatedExercises.length;

    if (hasMoreSets) {
      currentSetIndex += 1;
      session = session.copyWith(
        currentExerciseIndex: currentExerciseIndex,
        currentSetIndex: currentSetIndex,
        exercises: updatedExercises,
      );
      return;
    }

    if (hasMoreExercises) {
      currentExerciseIndex += 1;
      currentSetIndex = 0;
      session = session.copyWith(
        currentExerciseIndex: currentExerciseIndex,
        currentSetIndex: currentSetIndex,
        exercises: updatedExercises,
      );
      return;
    }

    session = session.copyWith(
      status: SessionStatus.completed,
      endedAt: DateTime.now(),
      currentExerciseIndex: currentExerciseIndex,
      currentSetIndex: currentSetIndex,
      exercises: updatedExercises,
    );
  }

  void skipCurrentSet() {
    final exercise = session.exercises[currentExerciseIndex];
    final existingSet = exercise.sets[currentSetIndex];
    final updatedSet = existingSet.copyWith(skipped: true, completed: false);

    final updatedExerciseSets = [...exercise.sets];
    updatedExerciseSets[currentSetIndex] = updatedSet;
    final updatedExercise = exercise.copyWith(sets: updatedExerciseSets);
    final updatedExercises = [...session.exercises];
    updatedExercises[currentExerciseIndex] = updatedExercise;

    if (currentSetIndex + 1 < updatedExercise.sets.length) {
      currentSetIndex += 1;
      session = session.copyWith(
        currentExerciseIndex: currentExerciseIndex,
        currentSetIndex: currentSetIndex,
        exercises: updatedExercises,
      );
      return;
    }

    if (currentExerciseIndex + 1 < updatedExercises.length) {
      currentExerciseIndex += 1;
      currentSetIndex = 0;
      session = session.copyWith(
        currentExerciseIndex: currentExerciseIndex,
        currentSetIndex: currentSetIndex,
        exercises: updatedExercises,
      );
      return;
    }

    session = session.copyWith(
      status: SessionStatus.incomplete,
      endedAt: DateTime.now(),
      exercises: updatedExercises,
    );
  }

  void finalizeIncomplete() {
    session = session.copyWith(
      status: SessionStatus.incomplete,
      endedAt: DateTime.now(),
    );
  }
}
