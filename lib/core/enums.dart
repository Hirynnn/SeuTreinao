enum DayStatus { rest, pending, completed, inProgress, incomplete }

enum SessionStatus { inProgress, completed, incomplete, cancelled }

extension DayStatusLabel on DayStatus {
  String get label {
    switch (this) {
      case DayStatus.rest:
        return 'Dia de descanso';
      case DayStatus.pending:
        return 'Treino pendente';
      case DayStatus.completed:
        return 'Treino concluído';
      case DayStatus.inProgress:
        return 'Em andamento';
      case DayStatus.incomplete:
        return 'Incompleto';
    }
  }
}

extension SessionStatusLabel on SessionStatus {
  String get label {
    switch (this) {
      case SessionStatus.inProgress:
        return 'Em andamento';
      case SessionStatus.completed:
        return 'Concluída';
      case SessionStatus.incomplete:
        return 'Incompleta';
      case SessionStatus.cancelled:
        return 'Cancelada';
    }
  }
}
