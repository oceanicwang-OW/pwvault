import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/services/clipboard_service.dart';

class _FakeClipboard implements ClipboardGateway {
  String? text;
  final sensitiveWrites = <String>[];

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeSensitiveText(String value) async {
    text = value;
    sensitiveWrites.add(value);
  }
}

void main() {
  test('copyPassword writes sensitive text immediately', () {
    fakeAsync((async) {
      final clipboard = _FakeClipboard();
      final service = ClipboardService(clipboard: clipboard);

      service.copyPassword('secret-1');
      async.flushMicrotasks();

      expect(clipboard.text, 'secret-1');
      expect(clipboard.sensitiveWrites, ['secret-1']);
    });
  });

  test('clears the clipboard after the configured timeout when unchanged', () {
    fakeAsync((async) {
      final clipboard = _FakeClipboard();
      final service = ClipboardService(
        clipboard: clipboard,
        clearAfter: const Duration(seconds: 30),
      );

      service.copyPassword('secret-1');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 29));
      async.flushMicrotasks();
      expect(clipboard.text, 'secret-1');

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(clipboard.text, '');
    });
  });

  test('does not clear clipboard content overwritten by the user', () {
    fakeAsync((async) {
      final clipboard = _FakeClipboard();
      final service = ClipboardService(
        clipboard: clipboard,
        clearAfter: const Duration(seconds: 30),
      );

      service.copyPassword('secret-1');
      async.flushMicrotasks();
      clipboard.text = 'user copied something else';

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(clipboard.text, 'user copied something else');
    });
  });

  test('copying a second password replaces the pending clear token', () {
    fakeAsync((async) {
      final clipboard = _FakeClipboard();
      final service = ClipboardService(
        clipboard: clipboard,
        clearAfter: const Duration(seconds: 30),
      );

      service.copyPassword('secret-1');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      service.copyPassword('secret-2');
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 20));
      async.flushMicrotasks();
      expect(clipboard.text, 'secret-2');

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(clipboard.text, '');
    });
  });
}
