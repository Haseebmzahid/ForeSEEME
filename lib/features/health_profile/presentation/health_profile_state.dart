/// State sealed class for HealthProfileNotifier operations.
sealed class HealthProfileState {
  const HealthProfileState();
}

class HealthProfileStateIdle extends HealthProfileState {
  const HealthProfileStateIdle();
}

class HealthProfileStateLoading extends HealthProfileState {
  const HealthProfileStateLoading();
}

class HealthProfileStateSaved extends HealthProfileState {
  const HealthProfileStateSaved();
}

class HealthProfileStateError extends HealthProfileState {
  final String message;
  const HealthProfileStateError(this.message);
}
