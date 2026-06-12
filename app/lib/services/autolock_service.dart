import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'vault_service.dart';

final autoLockTimeoutProvider =
    NotifierProvider<AutoLockTimeoutNotifier, Duration>(
  AutoLockTimeoutNotifier.new,
);

final autoLockServiceProvider = Provider<AutoLockService>((ref) {
  final service = AutoLockService(
    timeout: ref.watch(autoLockTimeoutProvider),
    isUnlocked: () => ref.read(vaultStateProvider) == VaultStatus.unlocked,
    onLock: () => ref.read(vaultProvider.notifier).lock(),
  );

  ref.onDispose(service.dispose);
  ref.listen(vaultStateProvider, (_, next) {
    if (next == VaultStatus.unlocked) {
      service.start();
    } else {
      service.stop();
    }
  });

  return service;
});

class AutoLockTimeoutNotifier extends Notifier<Duration> {
  @override
  Duration build() => const Duration(minutes: 5);

  void setTimeout(Duration timeout) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    state = timeout;
  }
}

class AutoLockService {
  final Duration timeout;
  final bool Function() isUnlocked;
  final Future<void> Function() onLock;

  Timer? _timer;
  bool _started = false;

  AutoLockService({
    required this.timeout,
    required this.isUnlocked,
    required this.onLock,
  });

  void start() {
    _started = true;
    _schedule();
  }

  void recordActivity() {
    if (!_started) return;
    _schedule();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (!isUnlocked()) {
        stop();
        return;
      }

      _started = false;
      _timer = null;
      unawaited(onLock());
    });
  }
}
