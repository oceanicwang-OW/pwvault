import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/services/autolock_service.dart';
import 'package:pwvault/services/vault_service.dart';

EntryMeta _meta(String id, String title) => EntryMeta(
  id: id,
  title: title,
  username: '',
  url: '',
  tags: const [],
  favorite: false,
  hasTotp: false,
  createdAt: 0,
  updatedAt: 0,
);

class _FakeSession implements VaultSession {
  final List<EntryMeta> entries;
  bool disposed = false;

  _FakeSession(this.entries);

  @override
  Future<List<EntryMeta>> listMeta() async => entries;

  @override
  Future<List<EntryMeta>> listTrash() async => const [];

  @override
  Future<EntryMeta> upsert(EntryDraft draft) async => entries.first;

  @override
  Future<String> revealPassword(String id) async => 'pw';

  @override
  Future<EntryDraft> getFull(String id) async => const EntryDraft(
    title: '',
    username: '',
    password: '',
    url: '',
    notes: '',
    tags: [],
    favorite: false,
  );

  @override
  Future<void> softDelete(String id) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {}

  @override
  void dispose() => disposed = true;
}

class _FakeBackend implements VaultBackend {
  final _FakeSession session;

  _FakeBackend(this.session);

  @override
  Future<VaultSession> create(String path, String password) =>
      unlock(path, password);

  @override
  Future<VaultSession> unlock(String path, String password) async => session;
}

ProviderContainer _containerWith(_FakeSession session) {
  final container = ProviderContainer(
    overrides: [
      vaultBackendProvider.overrideWithValue(_FakeBackend(session)),
      autoLockTimeoutProvider.overrideWith(() => _TestTimeoutNotifier()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _TestTimeoutNotifier extends AutoLockTimeoutNotifier {
  @override
  Duration build() => const Duration(seconds: 5);
}

void main() {
  test('idle timeout locks the vault and clears entryListProvider', () {
    fakeAsync((async) {
      final session = _FakeSession([_meta('1', 'GitHub')]);
      final container = _containerWith(session);

      container.read(vaultProvider.notifier).unlock('/v', 'master');
      async.flushMicrotasks();
      expect(container.read(vaultStateProvider), VaultStatus.unlocked);
      expect(container.read(entryListProvider), isNotEmpty);

      container.read(autoLockServiceProvider).start();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(container.read(vaultStateProvider), VaultStatus.locked);
      expect(container.read(entryListProvider), isEmpty);
      expect(session.disposed, isTrue);
    });
  });

  test('recordActivity resets the idle timer', () {
    fakeAsync((async) {
      final session = _FakeSession([_meta('1', 'GitHub')]);
      final container = _containerWith(session);

      container.read(vaultProvider.notifier).unlock('/v', 'master');
      async.flushMicrotasks();
      final service = container.read(autoLockServiceProvider)..start();

      async.elapse(const Duration(seconds: 4));
      service.recordActivity();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(container.read(vaultStateProvider), VaultStatus.unlocked);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(container.read(vaultStateProvider), VaultStatus.locked);
    });
  });

  test('stopping the service cancels pending auto-lock', () {
    fakeAsync((async) {
      final session = _FakeSession([_meta('1', 'GitHub')]);
      final container = _containerWith(session);

      container.read(vaultProvider.notifier).unlock('/v', 'master');
      async.flushMicrotasks();
      final service = container.read(autoLockServiceProvider)..start();

      service.stop();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(container.read(vaultStateProvider), VaultStatus.unlocked);
      expect(session.disposed, isFalse);
    });
  });
}
