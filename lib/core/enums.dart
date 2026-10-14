enum SessionStatus { inProgress, completed, incomplete, cancelled }

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
