import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final clipboardClearAfterProvider =
    NotifierProvider<ClipboardClearAfterNotifier, Duration>(
      ClipboardClearAfterNotifier.new,
    );

final clipboardGatewayProvider = Provider<ClipboardGateway>(
  (ref) => const FlutterClipboardGateway(),
);

final clipboardServiceProvider = Provider<ClipboardService>((ref) {
  final service = ClipboardService(
    clipboard: ref.watch(clipboardGatewayProvider),
    clearAfter: ref.watch(clipboardClearAfterProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

abstract interface class ClipboardGateway {
  Future<void> writeSensitiveText(String value);
  Future<String?> readText();
}

class FlutterClipboardGateway implements ClipboardGateway {
  const FlutterClipboardGateway();

  @override
  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> writeSensitiveText(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}

class ClipboardClearAfterNotifier extends Notifier<Duration> {
  @override
  Duration build() => const Duration(seconds: 30);

  void setClearAfter(Duration clearAfter) {
    if (clearAfter <= Duration.zero) {
      throw ArgumentError.value(clearAfter, 'clearAfter', 'must be positive');
    }
    state = clearAfter;
  }
}

class ClipboardService {
  final ClipboardGateway clipboard;
  final Duration clearAfter;

  Timer? _clearTimer;
  String? _copiedHash;

  ClipboardService({
    required this.clipboard,
    this.clearAfter = const Duration(seconds: 30),
  });

  Future<void> copyPassword(String password) async {
    _clearTimer?.cancel();
    final copiedHash = _hash(password);

    await clipboard.writeSensitiveText(password);
    _copiedHash = copiedHash;
    _clearTimer = Timer(clearAfter, () => unawaited(_clearIfUnchanged()));
  }

  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _copiedHash = null;
  }

  Future<void> _clearIfUnchanged() async {
    final copiedHash = _copiedHash;
    _clearTimer = null;
    _copiedHash = null;

    if (copiedHash == null) return;

    final current = await clipboard.readText();
    if (current != null && _hash(current) == copiedHash) {
      await clipboard.writeSensitiveText('');
    }
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
