import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/vault_service.dart';

/// 列表/编辑共享的 mock 条目存储（T2.10）。
///
/// 让"保存→列表即时刷新"在尚无真实库的阶段可演示；T2.10 之后接入真实
/// `entryListProvider` 与 Rust CRUD 时整体替换。
final mockEntryStoreProvider =
    NotifierProvider<MockEntryStore, List<EntryMeta>>(MockEntryStore.new);

class MockEntryStore extends Notifier<List<EntryMeta>> {
  @override
  List<EntryMeta> build() => _seedEntries();

  /// 新建或更新：按 [EntryDraft.id] 匹配，无 id 视为新建并分配 id、置顶。
  void upsert(EntryDraft draft) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingIndex = draft.id == null
        ? -1
        : state.indexWhere((e) => e.id == draft.id);

    final meta = EntryMeta(
      id: draft.id ?? 'entry-$now-${state.length}',
      title: draft.title,
      username: draft.username,
      url: draft.url,
      tags: draft.tags,
      favorite: draft.favorite,
      hasTotp: (draft.totpUri ?? '').isNotEmpty,
      createdAt: existingIndex == -1 ? now : state[existingIndex].createdAt,
      updatedAt: now,
    );

    if (existingIndex == -1) {
      state = [meta, ...state];
    } else {
      final next = [...state];
      next[existingIndex] = meta;
      state = next;
    }
  }
}

EntryMeta _seed(
  String id,
  String title, {
  required String username,
  required String url,
  required List<String> tags,
}) => EntryMeta(
  id: id,
  title: title,
  username: username,
  url: url,
  tags: tags,
  favorite: false,
  hasTotp: false,
  createdAt: 0,
  updatedAt: 0,
);

List<EntryMeta> _seedEntries() => [
  _seed(
    'taobao',
    '淘宝',
    username: 'owen_dev@163.com',
    url: 'taobao.com',
    tags: const ['个人'],
  ),
  _seed(
    'tmall',
    '天猫超市',
    username: '138****2046',
    url: 'tmall.com',
    tags: const ['个人'],
  ),
  _seed('jd', '京东', username: 'owen@jd.com', url: 'jd.com', tags: const ['购物']),
  _seed(
    'github',
    'GitHub',
    username: 'oceanicwang',
    url: 'github.com',
    tags: const ['工作'],
  ),
  _seed(
    'wechat',
    '微信',
    username: 'wxid_owen',
    url: 'weixin.qq.com',
    tags: const ['社交'],
  ),
  _seed(
    'cmb',
    '招商银行',
    username: '6225****8899',
    url: 'cmbchina.com',
    tags: const ['金融'],
  ),
];

/// 可选标签集合（mock 阶段固定）。
const kMockTagOptions = <String>['工作', '个人', '金融', '购物', '社交'];

/// 某条目的 mock 明文密码（T2.11 Enter 复制用；真实库接 `entry_reveal_password`）。
String mockPasswordFor(String entryId) => 'pw-$entryId-2024!';
