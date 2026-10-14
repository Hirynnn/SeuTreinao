import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:seu_treinao/core/app_theme.dart';
import 'package:seu_treinao/core/enums.dart';
import 'package:seu_treinao/core/models.dart';
import 'package:seu_treinao/services/database_service.dart';
import 'package:seu_treinao/services/notification_service.dart';
import 'package:seu_treinao/services/statistics_service.dart';
import 'package:seu_treinao/services/workout_rules.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting('pt_BR').then((_) => runApp(const SeuTreinaoApp()));
}

class SeuTreinaoApp extends StatefulWidget {
  const SeuTreinaoApp({super.key});

  @override
  State<SeuTreinaoApp> createState() => _SeuTreinaoAppState();
}

class _SeuTreinaoAppState extends State<SeuTreinaoApp> {
  late final Future<bool> _themePreference = _loadThemePreference();
  bool? _selectedTheme;

  Future<bool> _loadThemePreference() async {
    final value = await AppDatabase.instance.getSetting('is_light_theme');
    return value == 'true';
  }

  Future<void> _toggleTheme(bool isLight) async {
    await AppDatabase.instance.setSetting('is_light_theme', '$isLight');
    if (mounted) {
      setState(() => _selectedTheme = isLight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _themePreference,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            title: 'SeuTreinao',
            theme: buildSeuTreinaoTheme(Brightness.dark),
            home: _StartupErrorScreen(error: snapshot.error),
          );
        }
        final isLight = _selectedTheme ?? snapshot.data ?? false;
        return MaterialApp(
          title: 'SeuTreinao',
          debugShowCheckedModeBanner: false,
          theme: buildSeuTreinaoTheme(
            isLight ? Brightness.light : Brightness.dark,
          ),
          home: snapshot.hasData
              ? AppShell(isLightTheme: isLight, onToggleTheme: _toggleTheme)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        );
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Não foi possível carregar as preferências.\n$error'),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isLightTheme,
    required this.onToggleTheme,
  });

  final bool isLightTheme;
  final Future<void> Function(bool isLight) onToggleTheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    TrainingNotifications.instance.refreshNotifier.addListener(
      _onNotificationAction,
    );
    _restoreNotification();
  }

  Future<void> _restoreNotification() async {
    try {
      await TrainingNotifications.instance.initialize();
      final active = await AppDatabase.instance.getActiveSession();
      if (active != null) {
        await TrainingNotifications.instance.showForSession(active);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Não foi possível restaurar a notificação do treino: $error',
        );
      }
    }
  }

  void _onNotificationAction() => refresh();

  @override
  void dispose() {
    TrainingNotifications.instance.refreshNotifier.removeListener(
      _onNotificationAction,
    );
    super.dispose();
  }

  void refresh() => setState(() => _reload++);

  Future<void> openRoutine() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RoutineScreen(onSaved: refresh)),
    );
    refresh();
  }

  Future<void> resumeIncompleteSession(WorkoutSession session) async {
    var exerciseIndex = -1;
    var setIndex = -1;
    for (var i = 0; i < session.exercises.length; i++) {
      final pendingIndex = session.exercises[i].sets.indexWhere(
        (set) => !set.completed,
      );
      if (pendingIndex >= 0) {
        exerciseIndex = i;
        setIndex = pendingIndex;
        break;
      }
    }
    if (exerciseIndex < 0) {
      _showMessage('Não há séries pendentes para retomar.');
      return;
    }
    final resumed = session.copyWith(
      status: SessionStatus.inProgress,
      clearEndedAt: true,
      currentExerciseIndex: exerciseIndex,
      currentSetIndex: setIndex,
    );
    try {
      await AppDatabase.instance.saveSession(resumed);
    } catch (error) {
      _showMessage('Não foi possível retomar e salvar a sessão: $error');
      return;
    }
    try {
      final notificationShown = await TrainingNotifications.instance
          .showForSession(resumed, requestPermission: true);
      if (!notificationShown) {
        _showMessage(
          'A sessão foi retomada. Ative as notificações do app para usar o controle na notificação.',
        );
      }
    } catch (error) {
      _showMessage(
        'A sessão foi retomada, mas a notificação não pôde ser ativada: $error',
      );
    }
    await continueSession(resumed);
  }

  Future<void> openWorkout(Workout? workout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutEditorScreen(workout: workout, onSaved: refresh),
      ),
    );
    refresh();
  }

  Future<void> startWorkout(Workout workout) async {
    final active = await AppDatabase.instance.getActiveSession();
    if (active != null) {
      await continueSession(active);
      return;
    }
    if (workout.exercises.isEmpty ||
        workout.exercises.any((exercise) => exercise.sets.isEmpty)) {
      _showMessage('Adicione exercícios e séries antes de iniciar o treino.');
      return;
    }
    final catalog = await AppDatabase.instance.listExercises();
    final muscleGroups = {
      for (final exercise in catalog) exercise.id: exercise.muscleGroup,
    };
    final session = WorkoutSession(
      workoutId: workout.id!,
      workoutName: workout.name,
      startedAt: DateTime.now(),
      status: SessionStatus.inProgress,
      exercises: workout.exercises
          .map(
            (exercise) => SessionExercise(
              exerciseName: exercise.exerciseName,
              muscleGroup: muscleGroups[exercise.exerciseId] ?? 'Outros',
              orderIndex: exercise.orderIndex,
              sets: exercise.sets
                  .map(
                    (set) => SessionSet(
                      setNumber: set.setNumber,
                      plannedWeight: set.plannedWeight,
                      plannedReps: set.plannedReps,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
    try {
      await AppDatabase.instance.saveSession(session);
    } catch (error) {
      _showMessage('Não foi possível iniciar e salvar a sessão: $error');
      return;
    }
    final saved = await AppDatabase.instance.getActiveSession();
    if (saved != null) {
      try {
        final notificationShown = await TrainingNotifications.instance
            .showForSession(saved, requestPermission: true);
        if (!notificationShown) {
          _showMessage(
            'A sessão está salva. Ative as notificações do SeuTreinao no Android para usar os controles na notificação.',
          );
        }
      } catch (error) {
        _showMessage(
          'A sessão foi salva, mas a notificação não pôde ser ativada: $error',
        );
      }
      await continueSession(saved);
    }
  }

  Future<void> continueSession(WorkoutSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(session: session, onChanged: refresh),
      ),
    );
    refresh();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(
        key: ValueKey('dashboard-$_reload'),
        onConfigure: openRoutine,
        onStart: startWorkout,
        onContinue: continueSession,
        onViewWorkouts: () => setState(() => _selectedIndex = 1),
      ),
      WorkoutsScreen(
        key: ValueKey('workouts-$_reload'),
        onEdit: openWorkout,
        onStart: startWorkout,
      ),
      ExercisesScreen(key: ValueKey('exercises-$_reload')),
      HistoryScreen(
        key: ValueKey('history-$_reload'),
        onResume: resumeIncompleteSession,
      ),
      StatisticsScreen(key: ValueKey('stats-$_reload')),
    ];
    const titles = [
      'SeuTreinao',
      'Treinos',
      'Exercícios',
      'Histórico',
      'Estatísticas',
    ];

    return Scaffold(
      appBar: AppBar(
        title: _selectedIndex == 0
            ? Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CustomPaint(
                      painter: _BenchPressPainter(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.fitness_center,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(titles[_selectedIndex]),
                ],
              )
            : Text(titles[_selectedIndex]),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              tooltip: 'Editar rotina semanal',
              onPressed: openRoutine,
              icon: const Icon(Icons.calendar_month),
            ),
          IconButton(
            tooltip: widget.isLightTheme
                ? 'Ativar tema escuro'
                : 'Ativar tema claro',
            onPressed: () async {
              try {
                await widget.onToggleTheme(!widget.isLightTheme);
              } catch (error) {
                if (context.mounted) {
                  _showMessage('Não foi possível salvar o tema: $error');
                }
              }
            },
            icon: Icon(
              widget.isLightTheme
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Treinos',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            label: 'Exercícios',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Dados'),
        ],
      ),
    );
  }
}

class _BenchPressPainter extends CustomPainter {
  const _BenchPressPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final scale = size.width / 34;

    canvas
      ..save()
      ..scale(scale);
    canvas.drawLine(const Offset(2, 6), const Offset(32, 6), paint);
    canvas.drawLine(const Offset(5, 3), const Offset(5, 9), paint);
    canvas.drawLine(const Offset(8, 4), const Offset(8, 8), paint);
    canvas.drawLine(const Offset(26, 4), const Offset(26, 8), paint);
    canvas.drawLine(const Offset(29, 3), const Offset(29, 9), paint);
    canvas.drawLine(const Offset(9, 17), const Offset(25, 17), paint);
    canvas.drawLine(const Offset(11, 18), const Offset(8, 28), paint);
    canvas.drawLine(const Offset(23, 18), const Offset(26, 28), paint);
    canvas.drawLine(const Offset(8, 28), const Offset(13, 28), paint);
    canvas.drawLine(const Offset(24, 28), const Offset(29, 28), paint);
    canvas.drawLine(const Offset(9, 17), const Offset(9, 8), paint);
    canvas.drawLine(const Offset(25, 17), const Offset(25, 8), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BenchPressPainter oldDelegate) =>
      oldDelegate.color != color;
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onConfigure,
    required this.onStart,
    required this.onContinue,
    required this.onViewWorkouts,
  });

  final Future<void> Function() onConfigure;
  final Future<void> Function(Workout workout) onStart;
  final Future<void> Function(WorkoutSession session) onContinue;
  final VoidCallback onViewWorkouts;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSnapshot>(
      future: AppDatabase.instance.getDashboardSnapshot(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorView(error: snapshot.error);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final activeFuture = AppDatabase.instance.getActiveSession();
        return FutureBuilder<WorkoutSession?>(
          future: activeFuture,
          builder: (context, activeSnapshot) {
            if (activeSnapshot.hasError) {
              return _ErrorView(error: activeSnapshot.error);
            }
            final active = activeSnapshot.data;
            return FutureBuilder<List<TrainingDay>>(
              future: AppDatabase.instance.listTrainingDays(),
              builder: (context, scheduleSnapshot) {
                if (scheduleSnapshot.hasError) {
                  return _ErrorView(error: scheduleSnapshot.error);
                }
                if (!scheduleSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final schedule = scheduleSnapshot.data!;
                final todayAssignment = WeeklyWorkoutRules.getWorkoutForDate(
                  data.date,
                  schedule,
                );
                final todayWorkout = data.todaysWorkout;
                final nextWorkoutDate = WeeklyWorkoutRules.getNextWorkoutDate(
                  data.date,
                  schedule,
                );
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM', 'pt_BR').format(data.date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              active != null
                                  ? 'Treino em andamento'
                                  : todayAssignment == null
                                  ? 'Dia de descanso'
                                  : 'Treino de hoje',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              active?.workoutName ??
                                  todayWorkout?.name ??
                                  'Recupere as energias',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              active != null
                                  ? 'Sua sessão está salva e pronta para continuar.'
                                  : todayAssignment == null
                                  ? 'A rotina não será deslocada. Seu próximo treino continua no dia programado.'
                                  : data.status.label,
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: active != null
                                    ? () => onContinue(active)
                                    : todayWorkout != null
                                    ? () => onStart(todayWorkout)
                                    : data.nextWorkout != null
                                    ? onViewWorkouts
                                    : onConfigure,
                                icon: Icon(
                                  active != null
                                      ? Icons.play_arrow
                                      : todayWorkout != null
                                      ? Icons.fitness_center
                                      : Icons.tune,
                                ),
                                label: Text(
                                  active != null
                                      ? 'Continuar treino'
                                      : todayWorkout != null
                                      ? 'Iniciar treino'
                                      : data.nextWorkout != null
                                      ? 'Ver próximo treino'
                                      : 'Configurar rotina',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoCard(
                      icon: Icons.event_available,
                      title: 'Próximo treino',
                      value: data.nextWorkout == null || nextWorkoutDate == null
                          ? 'Nenhum treino programado'
                          : '${data.nextWorkout!.name} • ${DateFormat('EEEE, d MMM', 'pt_BR').format(nextWorkoutDate)}',
                    ),
                    _InfoCard(
                      icon: Icons.check_circle_outline,
                      title: 'Última sessão concluída',
                      value: data.lastCompletedSession == null
                          ? 'Ainda não há sessões concluídas'
                          : '${data.lastCompletedSession!.workoutName} • ${DateFormat('d MMM yyyy', 'pt_BR').format(data.lastCompletedSession!.startedAt)}',
                    ),
                    if (schedule.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: onConfigure,
                          icon: const Icon(Icons.calendar_month),
                          label: const Text('Configurar sua semana'),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class WorkoutsScreen extends StatelessWidget {
  const WorkoutsScreen({
    super.key,
    required this.onEdit,
    required this.onStart,
  });

  final Future<void> Function(Workout? workout) onEdit;
  final Future<void> Function(Workout workout) onStart;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Workout>>(
      future: AppDatabase.instance.listWorkouts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorView(error: snapshot.error);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final workouts = snapshot.data!;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => onEdit(null),
            icon: const Icon(Icons.add),
            label: const Text('Novo treino'),
          ),
          body: workouts.isEmpty
              ? const _EmptyView(
                  icon: Icons.fitness_center,
                  title: 'Nenhum treino cadastrado',
                  subtitle:
                      'Crie um treino para começar a planejar sua rotina.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: workouts.length,
                  itemBuilder: (context, index) {
                    final workout = workouts[index];
                    final setCount = workout.exercises.fold<int>(
                      0,
                      (sum, exercise) => sum + exercise.sets.length,
                    );
                    return Card(
                      child: ListTile(
                        title: Text(workout.name),
                        subtitle: Text(
                          '${workout.exercises.length} exercícios • $setCount séries',
                        ),
                        onTap: () => onEdit(workout),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Iniciar treino',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => onStart(workout),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await onEdit(workout);
                                } else if (value == 'duplicate') {
                                  await onEdit(
                                    Workout(
                                      name: '${workout.name} (cópia)',
                                      description: workout.description,
                                      exercises: workout.exercises
                                          .map(
                                            (exercise) => WorkoutExercise(
                                              exerciseName:
                                                  exercise.exerciseName,
                                              exerciseId: exercise.exerciseId,
                                              orderIndex: exercise.orderIndex,
                                              sets: exercise.sets
                                                  .map(
                                                    (set) => WorkoutSet(
                                                      setNumber: set.setNumber,
                                                      plannedWeight:
                                                          set.plannedWeight,
                                                      plannedReps:
                                                          set.plannedReps,
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  );
                                } else if (value == 'delete') {
                                  final confirmed = await _confirm(
                                    context,
                                    'Excluir ${workout.name}?',
                                  );
                                  if (confirmed) {
                                    try {
                                      await AppDatabase.instance.deleteWorkout(
                                        workout.id!,
                                      );
                                      if (context.mounted) {
                                        (context
                                                .findAncestorStateOfType<
                                                  _AppShellState
                                                >())
                                            ?.refresh();
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        _message(context, error.toString());
                                      }
                                    }
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Excluir'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({
    super.key,
    required this.workout,
    required this.onSaved,
  });

  final Workout? workout;
  final VoidCallback onSaved;

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late List<WorkoutExercise> _exercises;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.workout?.name ?? '');
    _description = TextEditingController(
      text: widget.workout?.description ?? '',
    );
    _exercises = [...?widget.workout?.exercises];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addExercises() async {
    final selected = await showDialog<List<Exercise>>(
      context: context,
      builder: (_) => const ExercisePickerDialog(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _exercises.addAll(
        selected.map(
          (exercise) => WorkoutExercise(
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            orderIndex: _exercises.length,
            sets: List.generate(
              3,
              (index) => WorkoutSet(
                setNumber: index + 1,
                plannedWeight: 0,
                plannedReps: 10,
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _addFromText() async {
    final result = await showDialog<List<Exercise>>(
      context: context,
      builder: (_) => const TextImportDialog(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _exercises.addAll(
        result.map(
          (exercise) => WorkoutExercise(
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            orderIndex: _exercises.length,
            sets: List.generate(
              3,
              (index) => WorkoutSet(
                setNumber: index + 1,
                plannedWeight: 0,
                plannedReps: 10,
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _editSets(int exerciseIndex) async {
    final edited = await showDialog<List<WorkoutSet>>(
      context: context,
      builder: (_) => SetPlannerDialog(exercise: _exercises[exerciseIndex]),
    );
    if (edited == null || !mounted) return;
    setState(
      () => _exercises[exerciseIndex] = _exercises[exerciseIndex].copyWith(
        sets: edited,
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _message(context, 'Informe o nome do treino.');
      return;
    }
    if (_exercises.isEmpty ||
        _exercises.any((exercise) => exercise.sets.isEmpty)) {
      _message(
        context,
        'Adicione ao menos um exercício com uma série planejada.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final workout = Workout(
        id: widget.workout?.id,
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        exercises: _exercises,
      );
      await AppDatabase.instance.saveWorkout(workout);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        _message(context, 'Não foi possível salvar o treino: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workout == null ? 'Novo treino' : 'Editar treino'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome do treino'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Exercícios',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Adicionar exercícios',
                icon: const Icon(Icons.add_circle_outline),
                onSelected: (value) =>
                    value == 'catalog' ? _addExercises() : _addFromText(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'catalog',
                    child: Text('Selecionar do catálogo'),
                  ),
                  PopupMenuItem(
                    value: 'text',
                    child: Text('Importar por texto'),
                  ),
                ],
              ),
            ],
          ),
          if (_exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Selecione exercícios do catálogo ou importe uma lista de nomes.',
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _exercises.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _exercises.removeAt(oldIndex);
                _exercises.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final exercise = _exercises[index];
              return Card(
                key: ValueKey('exercise-$index-${exercise.exerciseName}'),
                child: ListTile(
                  leading: const Icon(Icons.drag_handle),
                  title: Text(exercise.exerciseName),
                  subtitle: Text('${exercise.sets.length} séries'),
                  onTap: () => _editSets(index),
                  trailing: IconButton(
                    tooltip: 'Remover exercício do treino',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _exercises.removeAt(index)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(_saving ? 'Salvando...' : 'Salvar treino'),
          ),
        ],
      ),
    );
  }
}

class SetPlannerDialog extends StatefulWidget {
  const SetPlannerDialog({super.key, required this.exercise});

  final WorkoutExercise exercise;

  @override
  State<SetPlannerDialog> createState() => _SetPlannerDialogState();
}

class _SetPlannerDialogState extends State<SetPlannerDialog> {
  late List<_SetInput> _sets;

  @override
  void initState() {
    super.initState();
    _sets = widget.exercise.sets
        .map(
          (set) => _SetInput(
            set.plannedWeight.toString(),
            set.plannedReps.toString(),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final set in _sets) {
      set.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Séries • ${widget.exercise.exerciseName}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sets.isEmpty)
              const Text('Adicione séries e defina carga e repetições.'),
            ..._sets.asMap().entries.map(
              (entry) => Row(
                children: [
                  SizedBox(width: 32, child: Text('${entry.key + 1}')),
                  Expanded(
                    child: TextField(
                      controller: entry.value.weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Peso (kg)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: entry.value.reps,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Repetições',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remover série',
                    onPressed: () => setState(() {
                      _sets.removeAt(entry.key).dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _sets.add(_SetInput('0', '10'))),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar série'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final sets = <WorkoutSet>[];
            for (var index = 0; index < _sets.length; index++) {
              final weight = double.tryParse(
                _sets[index].weight.text.replaceAll(',', '.'),
              );
              final reps = int.tryParse(_sets[index].reps.text);
              if (weight == null || weight < 0 || reps == null || reps < 1) {
                _message(
                  context,
                  'Informe peso válido e pelo menos 1 repetição.',
                );
                return;
              }
              sets.add(
                WorkoutSet(
                  setNumber: index + 1,
                  plannedWeight: weight,
                  plannedReps: reps,
                ),
              );
            }
            Navigator.pop(context, sets);
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _SetInput {
  _SetInput(String weight, String reps)
    : weight = TextEditingController(text: weight),
      reps = TextEditingController(text: reps);

  final TextEditingController weight;
  final TextEditingController reps;

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

class ExercisePickerDialog extends StatefulWidget {
  const ExercisePickerDialog({super.key});

  @override
  State<ExercisePickerDialog> createState() => _ExercisePickerDialogState();
}

class _ExercisePickerDialogState extends State<ExercisePickerDialog> {
  final Set<int> _selected = {};
  String _query = '';
  String _group = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catálogo de exercícios'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Pesquisar',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _group,
              decoration: const InputDecoration(labelText: 'Grupo muscular'),
              items: ['Todos', ..._muscleGroups]
                  .map(
                    (group) => DropdownMenuItem(
                      value: group == 'Todos' ? '' : group,
                      child: Text(group),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _group = value ?? ''),
            ),
            Expanded(
              child: FutureBuilder<List<Exercise>>(
                future: AppDatabase.instance.listExercises(
                  query: _query,
                  muscleGroup: _group,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorView(error: snapshot.error);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    children: snapshot.data!
                        .map(
                          (exercise) => CheckboxListTile(
                            value: _selected.contains(exercise.id),
                            title: Text(exercise.name),
                            subtitle: Text(exercise.muscleGroup),
                            onChanged: (selected) => setState(() {
                              if (selected == true && exercise.id != null) {
                                _selected.add(exercise.id!);
                              }
                              if (selected != true) {
                                _selected.remove(exercise.id);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            final items = await AppDatabase.instance.listExercises(
              query: _query,
              muscleGroup: _group,
            );
            if (context.mounted) {
              Navigator.pop(
                context,
                items
                    .where((exercise) => _selected.contains(exercise.id))
                    .toList(),
              );
            }
          },
          child: Text('Adicionar (${_selected.length})'),
        ),
      ],
    );
  }
}

class TextImportDialog extends StatefulWidget {
  const TextImportDialog({super.key});

  @override
  State<TextImportDialog> createState() => _TextImportDialogState();
}

class _TextImportDialogState extends State<TextImportDialog> {
  final TextEditingController _input = TextEditingController();
  final Map<String, String> _renames = {};
  final Map<String, bool> _checked = {};
  List<String> _lines = [];
  Map<String, Exercise> _matches = {};
  bool _searched = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final names = _input.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet()
        .toList();
    final catalog = await AppDatabase.instance.listExercises();
    final matches = <String, Exercise>{};
    for (final name in names) {
      final normalized = name.toLowerCase();
      for (final exercise in catalog) {
        if (exercise.name.toLowerCase() == normalized) {
          matches[name] = exercise;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _lines = names;
      _matches = matches;
      _searched = true;
      for (final line in names) {
        _checked.putIfAbsent(line, () => true);
        _renames.putIfAbsent(line, () => line);
      }
    });
  }

  Future<void> _finish() async {
    final output = <Exercise>[];
    for (final line in _lines.where((value) => _checked[value] == true)) {
      final existing = _matches[line];
      if (existing != null) {
        output.add(existing);
      } else {
        final name = _renames[line]!.trim();
        if (name.isEmpty) continue;
        final created = Exercise(
          name: name,
          muscleGroup: 'Outros',
          isCustom: true,
        );
        await AppDatabase.instance.insertExercise(created);
        final matches = await AppDatabase.instance.listExercises(query: name);
        output.add(matches.firstWhere((exercise) => exercise.name == name));
      }
    }
    if (mounted) Navigator.pop(context, output);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar exercícios por texto'),
      content: SizedBox(
        width: 460,
        child: _searched
            ? ListView(
                shrinkWrap: true,
                children: _lines.map((line) {
                  final exercise = _matches[line];
                  return CheckboxListTile(
                    value: _checked[line] ?? false,
                    title: exercise == null
                        ? TextField(
                            decoration: const InputDecoration(
                              labelText: 'Não encontrado — corrija ou cadastre',
                            ),
                            controller: TextEditingController(
                              text: _renames[line],
                            ),
                            onChanged: (value) => _renames[line] = value,
                          )
                        : Text(exercise.name),
                    subtitle: Text(
                      exercise?.muscleGroup ?? 'Será cadastrado em Outros',
                    ),
                    onChanged: (value) =>
                        setState(() => _checked[line] = value ?? false),
                  );
                }).toList(),
              )
            : TextField(
                controller: _input,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Um exercício por linha',
                  border: OutlineInputBorder(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (!_searched)
          FilledButton(onPressed: _parse, child: const Text('Encontrar'))
        else
          FilledButton(
            onPressed: _finish,
            child: const Text('Adicionar ao treino'),
          ),
      ],
    );
  }
}

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  static const _days = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];
  static const _splits = [
    'ABC',
    'ABCD',
    'ABCDE',
    'Upper/Lower',
    'PPL',
    'Full Body',
    'Bro Split',
    'Personalizado',
  ];
  late Future<List<Workout>> _workoutsFuture;
  final Map<int, int?> _assignments = {};
  String _split = 'ABC';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final days = await db.listTrainingDays();
    _assignments
      ..clear()
      ..addEntries(days.map((day) => MapEntry(day.weekday, day.workoutId)));
    _split = await db.getSetting('training_split') ?? 'ABC';
    _workoutsFuture = db.listWorkouts();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final selectedDays = _assignments.entries
        .where((entry) => entry.value != null)
        .toList();
    if (selectedDays.isEmpty) {
      _message(context, 'Associe ao menos um treino a um dia.');
      return;
    }
    final workouts = await AppDatabase.instance.listWorkouts();
    if (!mounted) return;
    if (workouts.isEmpty) {
      _message(context, 'Crie um treino antes de configurar sua rotina.');
      return;
    }
    final active = await AppDatabase.instance.getActiveSession();
    if (!mounted) return;
    if (active != null) {
      final currentSchedule = await AppDatabase.instance.listTrainingDays();
      if (!mounted) return;
      final originalDay = currentSchedule.where(
        (day) => day.weekday == active.startedAt.weekday,
      );
      final originalWorkoutId = originalDay.isEmpty
          ? null
          : originalDay.first.workoutId;
      if (_assignments[active.startedAt.weekday] != originalWorkoutId) {
        final confirmed = await _confirm(
          context,
          'A rotina deste dia será alterada. A sessão em andamento continuará vinculada ao treino com que começou.',
        );
        if (!mounted || !confirmed) return;
      }
    }
    final days = selectedDays.map((entry) {
      final workout = workouts.where((item) => item.id == entry.value).first;
      return TrainingDay(
        weekday: entry.key,
        workoutId: workout.id,
        workoutName: workout.name,
      );
    }).toList();
    try {
      await AppDatabase.instance.saveRoutine(days, split: _split);
    } catch (error) {
      if (mounted) {
        _message(context, 'Não foi possível salvar a rotina: $error');
      }
      return;
    }
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rotina semanal')),
      body: FutureBuilder<List<Workout>>(
        future: _workoutsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _ErrorView(error: snapshot.error);
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final workouts = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Etapa 1 • Divisão',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _split,
                decoration: const InputDecoration(
                  labelText: 'Divisão de treino',
                ),
                items: _splits
                    .map(
                      (split) =>
                          DropdownMenuItem(value: split, child: Text(split)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _split = value ?? 'ABC'),
              ),
              const SizedBox(height: 24),
              Text(
                'Etapas 2 e 3 • Dias e treinos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Deixe como descanso os dias sem treino. Cada dia aceita no máximo um treino.',
              ),
              const SizedBox(height: 12),
              if (workouts.isEmpty)
                const _EmptyView(
                  icon: Icons.fitness_center,
                  title: 'Crie seu primeiro treino',
                  subtitle: 'Salve ao menos um treino e volte para associá-lo aos dias.',
                ),
              ...List.generate(7, (index) {
                final weekday = index + 1;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(_days[index])),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int?>(
                            initialValue: _assignments[weekday],
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              labelText: 'Programação',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Descanso'),
                              ),
                              ...workouts.map(
                                (workout) => DropdownMenuItem<int?>(
                                  value: workout.id,
                                  child: Text(
                                    workout.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              if (value == null) {
                                _assignments.remove(weekday);
                              } else {
                                _assignments[weekday] = value;
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: workouts.isEmpty ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Salvar rotina'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  String _query = '';
  String _group = '';
  int _reload = 0;

  Future<void> _editExercise([Exercise? exercise]) async {
    final name = TextEditingController(text: exercise?.name ?? '');
    var group = exercise?.muscleGroup ?? 'Outros';
    final result = await showDialog<Exercise>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(exercise == null ? 'Novo exercício' : 'Editar exercício'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Grupo muscular'),
                items: _muscleGroups
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => group = value ?? 'Outros'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  Exercise(
                    id: exercise?.id,
                    name: name.text.trim(),
                    muscleGroup: group,
                    isCustom: true,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (result == null) return;
    if (result.id == null) {
      await AppDatabase.instance.insertExercise(result);
    } else {
      await AppDatabase.instance.updateExercise(result);
    }
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editExercise(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Pesquisar exercícios',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: _group,
              decoration: const InputDecoration(labelText: 'Grupo muscular'),
              items: ['Todos', ..._muscleGroups]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value == 'Todos' ? '' : value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _group = value ?? ''),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Exercise>>(
              key: ValueKey(_reload),
              future: AppDatabase.instance.listExercises(
                query: _query,
                muscleGroup: _group,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) return _ErrorView(error: snapshot.error);
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final exercise = snapshot.data![index];
                    return Card(
                      child: ListTile(
                        title: Text(exercise.name),
                        subtitle: Text(exercise.muscleGroup),
                        trailing: exercise.isCustom
                            ? PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await _editExercise(exercise);
                                  } else {
                                    final confirm = await _confirm(
                                      context,
                                      'Excluir ${exercise.name}?',
                                    );
                                    if (!context.mounted) return;
                                    if (!confirm) return;
                                    try {
                                      await AppDatabase.instance.deleteExercise(
                                        exercise.id!,
                                      );
                                      if (context.mounted) {
                                        setState(() => _reload++);
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        _message(context, error.toString());
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Excluir'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.session,
    required this.onChanged,
  });

  final WorkoutSession session;
  final VoidCallback onChanged;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late WorkoutSession _session;
  late SessionProgress _progress;
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _reps = TextEditingController();
  Timer? _draftSaveTimer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _progress = SessionProgress(session: _session);
    _session = _progress.session;
    _syncInput();
  }

  void _syncInput() {
    if (_session.exercises.isEmpty) return;
    final index = _session.currentExerciseIndex.clamp(
      0,
      _session.exercises.length - 1,
    );
    final exercise = _session.exercises[index];
    if (exercise.sets.isEmpty) return;
    final setIndex = _session.currentSetIndex.clamp(
      0,
      exercise.sets.length - 1,
    );
    final set = exercise.sets[setIndex];
    _weight.text = (set.actualWeight ?? set.plannedWeight).toString();
    _reps.text = (set.actualReps ?? set.plannedReps).toString();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _session = _progress.session;
    await AppDatabase.instance.saveSession(_session);
    try {
      if (_session.status == SessionStatus.inProgress) {
        await TrainingNotifications.instance.showForSession(_session);
      } else {
        await TrainingNotifications.instance.cancel();
      }
    } catch (error) {
      if (mounted) {
        _message(
          context,
          'A sessão foi salva, mas a notificação não foi atualizada: $error',
        );
      }
    }
    if (mounted) {
      setState(() {
        _session = _progress.session;
        _syncInput();
      });
    }
    widget.onChanged();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 350), _saveDraft);
  }

  Future<void> _saveDraft() async {
    _draftSaveTimer = null;
    if (_session.status != SessionStatus.inProgress ||
        _session.exercises.isEmpty) {
      return;
    }
    final weight = double.tryParse(_weight.text.replaceAll(',', '.'));
    final reps = int.tryParse(_reps.text);
    if (weight == null || weight < 0 || reps == null || reps < 1) return;
    _progress.updateCurrentSetResults(weight: weight, reps: reps);
    _session = _progress.session;
    try {
      await AppDatabase.instance.saveSession(_session);
      widget.onChanged();
    } catch (error) {
      if (mounted) {
        _message(
          context,
          'Não foi possível salvar os valores da série: $error',
        );
      }
    }
  }

  Future<void> _completeSet() async {
    if (_saving || _progress.isFinished) return;
    final weight = double.tryParse(_weight.text.replaceAll(',', '.'));
    final reps = int.tryParse(_reps.text);
    if (weight == null || weight < 0 || reps == null || reps < 1) {
      _message(context, 'Informe peso válido e pelo menos 1 repetição.');
      return;
    }
    setState(() => _saving = true);
    try {
      _progress.completeCurrentSet(actualWeight: weight, actualReps: reps);
      await _persist();
      if (_progress.session.status == SessionStatus.completed && mounted) {
        await TrainingNotifications.instance.cancel();
        if (!mounted) return;
        _message(context, 'Treino concluído. Muito bem!');
      }
    } catch (error) {
      if (mounted) {
        _message(
          context,
          'Não foi possível salvar o progresso da série: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skipSet() async {
    _draftSaveTimer?.cancel();
    try {
      await _saveDraft();
      _progress.skipCurrentSet();
      await _persist();
    } catch (error) {
      if (mounted) {
        _message(
          context,
          'Não foi possível salvar o progresso da sessão: $error',
        );
      }
    }
  }

  Future<void> _finish({bool cancel = false}) async {
    final confirmed = await _confirm(
      context,
      cancel
          ? 'Cancelar esta sessão? Os registros já feitos serão preservados.'
          : 'Finalizar agora? Séries pendentes deixarão a sessão como incompleta.',
    );
    if (!mounted) return;
    if (!confirmed) return;
    _draftSaveTimer?.cancel();
    await _saveDraft();
    if (!mounted) return;
    if (cancel) {
      _session = _progress.session.copyWith(
        status: SessionStatus.cancelled,
        endedAt: DateTime.now(),
      );
    } else if (_progress.session.status == SessionStatus.inProgress) {
      _progress.finalizeIncomplete();
      _session = _progress.session;
    } else {
      _session = _progress.session;
    }
    try {
      await AppDatabase.instance.saveSession(_session);
      await TrainingNotifications.instance.cancel();
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        _message(context, 'Não foi possível finalizar a sessão: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exerciseIndex = _session.currentExerciseIndex.clamp(
      0,
      _session.exercises.length - 1,
    );
    final exercise = _session.exercises[exerciseIndex];
    final setIndex = _session.currentSetIndex.clamp(
      0,
      exercise.sets.length - 1,
    );
    final currentSet = exercise.sets[setIndex];
    final totalSets = _session.exercises.fold<int>(
      0,
      (sum, item) => sum + item.sets.length,
    );
    final completed = _session.exercises
        .expand((item) => item.sets)
        .where((set) => set.completed)
        .length;
    final duration = DateTime.now().difference(_session.startedAt);
    final active = _session.status == SessionStatus.inProgress;
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.workoutName),
        actions: [
          if (active)
            PopupMenuButton<String>(
              onSelected: (value) => _finish(cancel: value == 'cancel'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'finish', child: Text('Finalizar treino')),
                PopupMenuItem(value: 'cancel', child: Text('Cancelar treino')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tempo decorrido: ${_durationLabel(duration)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: totalSets == 0 ? 0 : completed / totalSets,
          ),
          const SizedBox(height: 8),
          Text('$completed de $totalSets séries concluídas'),
          const SizedBox(height: 24),
          if (active) ...[
            Text(
              'Exercício ${exerciseIndex + 1} de ${_session.exercises.length}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              exercise.exerciseName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      'Série ${setIndex + 1} de ${exercise.sets.length}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Planejado: ${currentSet.plannedWeight} kg × ${currentSet.plannedReps} repetições',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weight,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Peso realizado (kg)',
                            ),
                            onChanged: (_) => _scheduleDraftSave(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _reps,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Repetições',
                            ),
                            onChanged: (_) => _scheduleDraftSave(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _completeSet,
                        icon: const Icon(Icons.check),
                        label: const Text('Concluir série'),
                      ),
                    ),
                    TextButton(
                      onPressed: _skipSet,
                      child: const Text('Pular série'),
                    ),
                    TextButton(
                      onPressed: _progress.canGoToPreviousSet
                          ? () async {
                              _progress.goToPreviousSet();
                              await _persist();
                            }
                          : null,
                      child: const Text('Voltar à série anterior'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Icon(
              _session.status == SessionStatus.completed
                  ? Icons.check_circle
                  : Icons.flag_circle,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _session.status.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: active ? () => _finish() : null,
            icon: const Icon(Icons.flag),
            label: const Text('Finalizar treino'),
          ),
          if (active)
            TextButton.icon(
              onPressed: () => _finish(cancel: true),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar sessão'),
            ),
          const Divider(height: 32),
          Text(
            'Progresso por exercício',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ..._session.exercises.map((item) {
            final done = item.sets.where((set) => set.completed).length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.exerciseName),
              subtitle: Text('$done/${item.sets.length} séries concluídas'),
            );
          }),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.onResume});

  final Future<void> Function(WorkoutSession session) onResume;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _status = 'Todas';
  int _days = 0;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items:
                      [
                            'Todas',
                            ...SessionStatus.values.map((item) => item.label),
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'Todas'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _days,
                  decoration: const InputDecoration(labelText: 'Período'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Todo período')),
                    DropdownMenuItem(value: 7, child: Text('7 dias')),
                    DropdownMenuItem(value: 30, child: Text('30 dias')),
                    DropdownMenuItem(value: 90, child: Text('90 dias')),
                  ],
                  onChanged: (value) => setState(() => _days = value ?? 0),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<WorkoutSession>>(
            key: ValueKey(_reload),
            future: AppDatabase.instance.listSessions(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorView(error: snapshot.error);
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cutoff = _days == 0
                  ? null
                  : DateTime.now().subtract(Duration(days: _days));
              final filtered = snapshot.data!.where((session) {
                final matchesStatus =
                    _status == 'Todas' || session.status.label == _status;
                return matchesStatus &&
                    (cutoff == null || session.startedAt.isAfter(cutoff));
              }).toList();
              if (filtered.isEmpty) {
                return const _EmptyView(
                  icon: Icons.history,
                  title: 'Histórico vazio',
                  subtitle: 'Suas sessões ficarão registradas aqui.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final session = filtered[index];
                  final sets = session.exercises
                      .expand((exercise) => exercise.sets)
                      .toList();
                  final completeCount = sets
                      .where((set) => set.completed)
                      .length;
                  final duration = session.endedAt?.difference(
                    session.startedAt,
                  );
                  return Card(
                    child: ListTile(
                      title: Text(session.workoutName),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy • HH:mm').format(session.startedAt)}\n'
                        '${duration == null ? 'Em andamento' : _durationLabel(duration)} • $completeCount séries • ${session.status.label}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(
                            session: session,
                            onResume: widget.onResume,
                          ),
                        ),
                      ).then((_) => setState(() => _reload++)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.onResume,
  });

  final WorkoutSession session;
  final Future<void> Function(WorkoutSession session) onResume;

  @override
  Widget build(BuildContext context) {
    final ended = session.endedAt;
    return Scaffold(
      appBar: AppBar(title: Text(session.workoutName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(DateFormat('dd/MM/yyyy • HH:mm').format(session.startedAt)),
          Text('Status: ${session.status.label}'),
          if (ended != null)
            Text(
              'Duração: ${_durationLabel(ended.difference(session.startedAt))}',
            ),
          if (session.status == SessionStatus.incomplete &&
              session.exercises.any(
                (exercise) => exercise.sets.any((set) => !set.completed),
              ))
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: FilledButton.icon(
                onPressed: () => onResume(session),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Retomar sessão'),
              ),
            ),
          const Divider(height: 28),
          ...session.exercises.map(
            (exercise) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.exerciseName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...exercise.sets.map(
                      (set) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          set.completed
                              ? Icons.check_circle
                              : set.skipped
                              ? Icons.skip_next
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text('Série ${set.setNumber}'),
                        subtitle: Text(
                          'Planejado ${set.plannedWeight} kg × ${set.plannedReps}'
                          '${set.completed ? ' • Realizado ${set.actualWeight} kg × ${set.actualReps}' : ''}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkoutSession>>(
      future: AppDatabase.instance.listSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorView(error: snapshot.error);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final stats = calculateTrainingStatistics(snapshot.data!);
        final mostPerformed = stats.exerciseSetCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topMuscles = stats.muscleGroupSetCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final averageStartMinutes = stats.averageStartMinute;
        final averageStartLabel = averageStartMinutes == null
            ? '—'
            : '${((averageStartMinutes ~/ 60) % 24).toString().padLeft(2, '0')}:${(averageStartMinutes % 60).toString().padLeft(2, '0')}';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Resumo geral', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _StatCard(
              title: 'Sessões concluídas',
              value: '${stats.completedSessions}',
            ),
            _StatCard(
              title: 'Sessões incompletas',
              value: '${stats.incompleteSessions}',
            ),
            _StatCard(
              title: 'Dias efetivamente treinados',
              value: '${stats.trainedDays}',
            ),
            _StatCard(
              title: 'Média de sessões concluídas por semana',
              value: stats.averageSessionsPerWeek == null
                  ? '—'
                  : stats.averageSessionsPerWeek!.toStringAsFixed(1),
            ),
            _StatCard(
              title: 'Duração média concluída',
              value: stats.averageDurationMinutes == null
                  ? '—'
                  : '${stats.averageDurationMinutes!.round()} min',
            ),
            _StatCard(
              title: 'Horário médio de início',
              value: averageStartLabel,
            ),
            const SizedBox(height: 12),
            Text(
              'Exercícios mais realizados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (mostPerformed.isEmpty)
              const ListTile(title: Text('Dados insuficientes')),
            ...mostPerformed.take(5).map((entry) {
              final last = stats.exerciseLastWeights[entry.key];
              final max = stats.exerciseMaxWeights[entry.key];
              return Card(
                child: ListTile(
                  title: Text(entry.key),
                  subtitle: Text(
                    '${entry.value} séries concluídas • Última carga: ${last == null ? '—' : '$last kg'} • Maior: ${max == null ? '—' : '$max kg'}',
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Text(
              'Grupos musculares mais treinados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (topMuscles.isEmpty)
              const ListTile(title: Text('Dados insuficientes')),
            ...topMuscles
                .take(5)
                .map(
                  (entry) => ListTile(
                    title: Text(entry.key),
                    trailing: Text('${entry.value} séries'),
                  ),
                ),
            const SizedBox(height: 6),
            const Text(
              'As estatísticas contam séries realizadas (incluindo sessões incompletas). A média semanal considera o intervalo desde a sessão mais antiga. Sessões canceladas são excluídas.',
            ),
          ],
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Não foi possível carregar os dados.\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

const _muscleGroups = [
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
];

Future<bool> _confirm(BuildContext context, String text) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours == 0 ? '$minutes min' : '${hours}h ${minutes}min';
}
