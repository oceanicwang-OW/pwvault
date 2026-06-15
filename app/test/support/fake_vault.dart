import 'package:pwvault/services/vault_service.dart';

/// 内存版 VaultBackend/Session，供 UI 测试注入一个已解锁、已播种的库，
/// 替代旧的 mock 存储。支持 list/upsert/reveal/getFull/softDelete CRUD。
class FakeVaultBackend implements VaultBackend {
  final FakeVaultSession session;

  FakeVaultBackend([List<EntryDraft> seeds = const []])
    : session = FakeVaultSession(seeds);

  @override
  Future<VaultSession> create(String path, String password) async => session;

  @override
  Future<VaultSession> unlock(String path, String password) async => session;
}

class FakeVaultSession implements VaultSession {
  final List<String> _order = [];
  final Map<String, EntryDraft> _full = {};
  final Map<String, int> _createdAt = {};
  final Map<String, int> _updatedAt = {};
  final Set<String> _trash = {};
  int _seq = 0;

  FakeVaultSession([List<EntryDraft> seeds = const []]) {
    for (final draft in seeds) {
      _put(draft, prepend: false);
    }
  }

  EntryMeta _metaOf(String id) {
    final d = _full[id]!;
    return EntryMeta(
      id: id,
      title: d.title,
      username: d.username,
      url: d.url,
      tags: d.tags,
      favorite: d.favorite,
      hasTotp: (d.totpUri ?? '').isNotEmpty,
      createdAt: _createdAt[id]!,
      updatedAt: _updatedAt[id]!,
    );
  }

  EntryMeta _put(EntryDraft draft, {required bool prepend}) {
    final seq = ++_seq;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = draft.id ?? 'entry-$seq';
    final stored = EntryDraft(
      id: id,
      title: draft.title,
      username: draft.username,
      password: draft.password,
      url: draft.url,
      notes: draft.notes,
      totpUri: draft.totpUri,
      tags: draft.tags,
      favorite: draft.favorite,
    );
    final isNew = !_order.contains(id);
    _full[id] = stored;
    _updatedAt[id] = now;
    if (isNew) {
      _createdAt[id] = now;
      if (prepend) {
        _order.insert(0, id);
      } else {
        _order.add(id);
      }
    }
    return _metaOf(id);
  }

  @override
  Future<List<EntryMeta>> listMeta() async =>
      [for (final id in _order) if (!_trash.contains(id)) _metaOf(id)];

  @override
  Future<List<EntryMeta>> listTrash() async =>
      [for (final id in _order) if (_trash.contains(id)) _metaOf(id)];

  @override
  Future<EntryMeta> upsert(EntryDraft draft) async =>
      _put(draft, prepend: draft.id == null);

  @override
  Future<String> revealPassword(String id) async => _full[id]?.password ?? '';

  @override
  Future<EntryDraft> getFull(String id) async => _full[id]!;

  @override
  Future<void> softDelete(String id) async => _trash.add(id);

  @override
  Future<void> restore(String id) async => _trash.remove(id);

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {}

  @override
  void dispose() {}
}

/// 演示库：6 条固定条目，沿用旧 mock 的 id/标题以便测试断言稳定。
List<EntryDraft> demoSeeds() => [
  _seed('taobao', '淘宝', 'owen_dev@163.com', 'taobao.com', ['个人']),
  _seed('tmall', '天猫超市', '138****2046', 'tmall.com', ['个人']),
  _seed('jd', '京东', 'owen@jd.com', 'jd.com', ['购物']),
  _seed('github', 'GitHub', 'oceanicwang', 'github.com', ['工作']),
  _seed('wechat', '微信', 'wxid_owen', 'weixin.qq.com', ['社交']),
  _seed('cmb', '招商银行', '6225****8899', 'cmbchina.com', ['金融']),
];

/// 某条目的演示密码（与旧 mockPasswordFor 形式一致，便于断言）。
String demoPasswordFor(String id) => 'pw-$id-2024!';

EntryDraft _seed(
  String id,
  String title,
  String username,
  String url,
  List<String> tags,
) => EntryDraft(
  id: id,
  title: title,
  username: username,
  password: demoPasswordFor(id),
  url: url,
  notes: '',
  tags: tags,
  favorite: false,
);
