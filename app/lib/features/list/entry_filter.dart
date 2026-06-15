import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/vault_service.dart';

/// 列表当前视图过滤（侧边栏选择）。
sealed class EntryFilter {
  const EntryFilter();
}

class AllEntriesFilter extends EntryFilter {
  const AllEntriesFilter();
}

class FavoritesFilter extends EntryFilter {
  const FavoritesFilter();
}

class TrashFilter extends EntryFilter {
  const TrashFilter();
}

class TagFilter extends EntryFilter {
  final String tag;
  const TagFilter(this.tag);

  @override
  bool operator ==(Object other) =>
      other is TagFilter && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;
}

final entryFilterProvider = NotifierProvider<EntryFilterNotifier, EntryFilter>(
  EntryFilterNotifier.new,
);

class EntryFilterNotifier extends Notifier<EntryFilter> {
  @override
  EntryFilter build() => const AllEntriesFilter();

  void set(EntryFilter filter) => state = filter;
}

/// 回收站条目（软删除）。库状态变化时重取，删除/恢复后自动刷新。
final trashListProvider = FutureProvider<List<EntryMeta>>((ref) async {
  ref.watch(vaultProvider); // 删除/恢复改变库状态 → 重新拉取
  if (ref.read(vaultStateProvider) != VaultStatus.unlocked) return const [];
  return ref.read(vaultProvider.notifier).listTrash();
});

/// 当前视图（未搜索）的条目：按过滤选择数据源并过滤。
final viewEntriesProvider = Provider<List<EntryMeta>>((ref) {
  final filter = ref.watch(entryFilterProvider);
  if (filter is TrashFilter) {
    return ref.watch(trashListProvider).asData?.value ?? const [];
  }
  final all = ref.watch(entryListProvider);
  return switch (filter) {
    FavoritesFilter() => [for (final e in all) if (e.favorite) e],
    TagFilter(:final tag) => [for (final e in all) if (e.tags.contains(tag)) e],
    _ => all,
  };
});

/// 全部未删除条目里出现过的标签集合（侧边栏标签区，按字母序）。
final allTagsProvider = Provider<List<String>>((ref) {
  final all = ref.watch(entryListProvider);
  final tags = <String>{for (final e in all) ...e.tags};
  return tags.toList()..sort();
});
