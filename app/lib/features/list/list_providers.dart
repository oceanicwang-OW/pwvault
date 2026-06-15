import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/search_index.dart';
import 'entry_filter.dart';

/// 列表栏共享状态（T2.11）：把搜索词、选中条目、搜索框焦点提到 provider，
/// 让全局快捷键（聚焦搜索 / ↑↓ 导航 / Enter 复制）与列表面板共享同一份状态。

/// 经过 150ms debounce 后生效的搜索词。
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// 当前选中条目 id（null 表示未选中）。
final selectedEntryIdProvider =
    NotifierProvider<SelectedEntryNotifier, String?>(SelectedEntryNotifier.new);

class SelectedEntryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// 列表搜索框焦点节点，供 Ctrl/Cmd+F 聚焦。
final listSearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'list-search');
  ref.onDispose(node.dispose);
  return node;
});

/// 当前视图条目的搜索索引；仅在视图（过滤/列表/最近使用）变化时重建，
/// 不随每次按键重建（PDR 6.1）。
final viewIndexProvider = Provider<SearchIndexService>((ref) {
  final entries = ref.watch(viewEntriesProvider);
  final recentUse = ref.watch(entryRecentUseProvider);
  return SearchIndexService.fromEntries(entries, recentUse: recentUse);
});

/// 当前可见（已过滤排序）的搜索结果，列表渲染与键盘导航共用同一顺序。
final searchOutcomeProvider = Provider<SearchOutcome>((ref) {
  final index = ref.watch(viewIndexProvider);
  final query = ref.watch(searchQueryProvider);
  return index.searchDetailed(query);
});
