import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/database_service.dart';
import 'package:seu_treinao/services/workout_rules.dart';

class TrainingNotifications {
  TrainingNotifications._();

  static final TrainingNotifications instance = TrainingNotifications._();
  static const _notificationId = 17;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || defaultTargetPlatform != TargetPlatform.android) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse:
          trainingNotificationBackgroundHandler,
    );
    _initialized = true;
  }

  Future<bool> showForSession(
    WorkoutSession session, {
    bool requestPermission = false,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        session.status != SessionStatus.inProgress ||
        session.exercises.isEmpty) {
      return false;
    }
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (requestPermission) {
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) return false;
    }
    final exerciseIndex = session.currentExerciseIndex.clamp(
      0,
      session.exercises.length - 1,
    );
    final exercise = session.exercises[exerciseIndex];
    if (exercise.sets.isEmpty) return false;
    final setIndex = session.currentSetIndex.clamp(0, exercise.sets.length - 1);
    final set = exercise.sets[setIndex];
    await _plugin.show(
      id: _notificationId,
      title: session.workoutName,
      body:
          '${exercise.exerciseName} • Série ${setIndex + 1}/${exercise.sets.length} • '
          '${set.plannedWeight} kg × ${set.plannedReps}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'active_training',
          'Treino em andamento',
          channelDescription: 'Progresso da sessão atual de treino.',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          onlyAlertOnce: true,
          actions: [
            AndroidNotificationAction(
              'complete_set',
              'Concluir série',
              showsUserInterface: false,
              cancelNotification: false,
            ),
          ],
        ),
      ),
      payload: 'active_training',
    );
    return true;
  }

  Future<void> cancel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();
    await _plugin.cancel(id: _notificationId);
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    if (response.actionId == 'complete_set') {
      await _completeActiveSet();
      return;
    }
    refreshNotifier.value++;
  }

  Future<void> _completeActiveSet() async {
    final active = await AppDatabase.instance.getActiveSession();
    if (active == null ||
        active.exercises.isEmpty ||
        active.currentExerciseIndex >= active.exercises.length) {
      await cancel();
      return;
    }
    final progress = SessionProgress(session: active);
    progress.completeCurrentSet();
    await AppDatabase.instance.saveSession(progress.session);
    if (progress.session.status == SessionStatus.inProgress) {
      await showForSession(progress.session);
    } else {
      await cancel();
    }
    refreshNotifier.value++;
  }
}

@pragma('vm:entry-point')
void trainingNotificationBackgroundHandler(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (response.actionId == 'complete_set') {
    TrainingNotifications.instance._completeActiveSet();
  }
}
