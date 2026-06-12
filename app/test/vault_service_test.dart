import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/services/vault_service.dart';

EntryMeta _meta(String id, String title, {int? deletedAt}) => EntryMeta(
  id: id,
  title: title,
  username: '',
  url: '',
  tags: const [],
  favorite: false,
  hasTotp: false,
  createdAt: 0,
  updatedAt: 0,
  deletedAt: deletedAt,
);

EntryDraft _draft(String title) => EntryDraft(
  title: title,
  username: '',
  password: '',
  url: '',
  notes: '',
  tags: const [],
  favorite: false,
);

/// 内存假会话：记录 dispose、支持 upsert 追加。
class _FakeSession implements VaultSession {
  List<EntryMeta> entries;
  bool disposed = false;
  _FakeSession([this.entries = const []]);

  @override
  Future<List<EntryMeta>> listMeta() async =>
      entries.where((e) => e.deletedAt == null).toList();

  @override
  Future<List<EntryMeta>> listTrash() async =>
      entries.where((e) => e.deletedAt != null).toList();

  @override
  Future<EntryMeta> upsert(EntryDraft draft) async {
    final meta = _meta(draft.id ?? 'gen-${entries.length}', draft.title);
    entries = [...entries, meta];
    return meta;
  }

  @override
  Future<String> revealPassword(String id) async => 'pw-$id';

  @override
  Future<EntryDraft> getFull(String id) async => _draft('full-$id');

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
  final _FakeSession? session;
  final Object? error;
  _FakeBackend({this.session, this.error});

  @override
  Future<VaultSession> create(String path, String password) =>
      unlock(path, password);

  @override
  Future<VaultSession> unlock(String path, String password) async {
    if (error != null) throw error!;
    return session!;
  }
}

ProviderContainer _containerWith(VaultBackend backend) {
  final container = ProviderContainer(
    overrides: [vaultBackendProvider.overrideWithValue(backend)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('unlock 失败：保持锁定并清空状态，抛领域异常', () async {
    final container = _containerWith(
      _FakeBackend(error: const WrongPasswordException('WRONG_PASSWORD: x')),
    );
    final notifier = container.read(vaultProvider.notifier);

    await expectLater(
      notifier.unlock('/v', 'bad'),
      throwsA(isA<WrongPasswordException>()),
    );
    expect(container.read(vaultStateProvider), VaultStatus.locked);
    expect(container.read(entryListProvider), isEmpty);
  });

  test('unlock 成功填充状态；lock 释放会话并清空', () async {
    final session = _FakeSession([_meta('1', 'a'), _meta('2', 'b')]);
    final container = _containerWith(_FakeBackend(session: session));
    final notifier = container.read(vaultProvider.notifier);

    await notifier.unlock('/v', 'master');
    expect(container.read(vaultStateProvider), VaultStatus.unlocked);
    expect(container.read(entryListProvider).length, 2);

    await notifier.lock();
    expect(container.read(vaultStateProvider), VaultStatus.locked);
    expect(container.read(entryListProvider), isEmpty);
    expect(session.disposed, isTrue, reason: '锁定必须释放会话以 zeroize 密钥');
  });

  test('锁定状态下操作抛 VaultLockedException', () async {
    final container = _containerWith(_FakeBackend(session: _FakeSession()));
    final notifier = container.read(vaultProvider.notifier);

    await expectLater(
      notifier.upsert(_draft('t')),
      throwsA(isA<VaultLockedException>()),
    );
    await expectLater(
      notifier.revealPassword('x'),
      throwsA(isA<VaultLockedException>()),
    );
  });

  test('upsert 后刷新条目列表', () async {
    final session = _FakeSession([_meta('1', 'a')]);
    final container = _containerWith(_FakeBackend(session: session));
    final notifier = container.read(vaultProvider.notifier);

    await notifier.unlock('/v', 'master');
    expect(container.read(entryListProvider).length, 1);

    await notifier.upsert(_draft('b'));
    expect(container.read(entryListProvider).length, 2);
  });

  test('listTrash 走会话（已删除条目）', () async {
    final session = _FakeSession([
      _meta('1', 'live'),
      _meta('2', 'gone', deletedAt: 123),
    ]);
    final container = _containerWith(_FakeBackend(session: session));
    final notifier = container.read(vaultProvider.notifier);

    await notifier.unlock('/v', 'master');
    expect(container.read(entryListProvider).length, 1);
    final trash = await notifier.listTrash();
    expect(trash.length, 1);
    expect(trash.first.id, '2');
  });
}
