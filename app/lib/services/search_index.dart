import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinyin/pinyin.dart';

import 'vault_service.dart';

final entryRecentUseProvider =
    NotifierProvider<EntryRecentUseNotifier, Map<String, int>>(
  EntryRecentUseNotifier.new,
);

final searchIndexProvider = Provider<SearchIndexService>(
  (ref) => SearchIndexService.fromEntries(
    ref.watch(entryListProvider),
    recentUse: ref.watch(entryRecentUseProvider),
  ),
);

class EntryRecentUseNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void markUsed(String entryId, {int? at}) {
    state = {
      ...state,
      entryId: at ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  void replaceAll(Map<String, int> recentUse) {
    state = Map.unmodifiable(recentUse);
  }
}

class SearchIndexService {
  final List<_IndexedEntry> _entries;

  SearchIndexService._(this._entries);

  factory SearchIndexService.fromEntries(
    List<EntryMeta> entries, {
    Map<String, int> recentUse = const {},
  }) {
    return SearchIndexService._([
      for (var i = 0; i < entries.length; i++)
        if (entries[i].deletedAt == null)
          _IndexedEntry.from(
            entries[i],
            recentUseAt: recentUse[entries[i].id] ?? 0,
            position: i,
          ),
    ]);
  }

  List<EntryMeta> search(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) {
      return _sortedByRecent(_entries).map((e) => e.meta).toList();
    }

    final hits = <_SearchHit>[];
    for (final entry in _entries) {
      final rank = entry.rank(tokens);
      if (rank != null) {
        hits.add(_SearchHit(entry, rank));
      }
    }

    hits.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      if (rank != 0) return rank;
      final recentUse = b.entry.recentUseAt.compareTo(a.entry.recentUseAt);
      if (recentUse != 0) return recentUse;
      return a.entry.position.compareTo(b.entry.position);
    });
    return hits.map((hit) => hit.entry.meta).toList();
  }

  /// 在 [search] 排序结果之上附带"是否拼音命中"标记，供列表栏结果区标注。
  SearchOutcome searchDetailed(String query) {
    final entries = search(query);
    final tokens = _tokenize(query);
    if (tokens.isEmpty || entries.isEmpty) {
      return SearchOutcome(entries: entries, pinyinMatched: false);
    }
    final matchedIds = {for (final meta in entries) meta.id};
    final pinyinMatched = _entries.any(
      (entry) =>
          matchedIds.contains(entry.meta.id) &&
          entry.isPinyinTitleMatch(tokens),
    );
    return SearchOutcome(entries: entries, pinyinMatched: pinyinMatched);
  }

  /// 暴露分词逻辑，便于列表栏复用同一套关键词做命中高亮。
  static List<String> tokenize(String query) => _tokenize(query);

  static List<String> _tokenize(String query) => query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  static List<_IndexedEntry> _sortedByRecent(List<_IndexedEntry> entries) =>
      [...entries]
        ..sort((a, b) {
          final recentUse = b.recentUseAt.compareTo(a.recentUseAt);
          if (recentUse != 0) return recentUse;
          return a.position.compareTo(b.position);
        });
}

/// 列表栏搜索结果：排序后的条目，外加结果区是否应标注"拼音匹配"。
class SearchOutcome {
  final List<EntryMeta> entries;
  final bool pinyinMatched;

  const SearchOutcome({required this.entries, required this.pinyinMatched});
}

class _SearchHit {
  final _IndexedEntry entry;
  final int rank;

  const _SearchHit(this.entry, this.rank);
}

class _IndexedEntry {
  final EntryMeta meta;
  final int recentUseAt;
  final int position;
  final String title;
  final String titlePinyin;
  final String titleInitials;
  final String otherBlob;
  final String searchBlob;

  _IndexedEntry({
    required this.meta,
    required this.recentUseAt,
    required this.position,
    required this.title,
    required this.titlePinyin,
    required this.titleInitials,
    required this.otherBlob,
    required this.searchBlob,
  });

  factory _IndexedEntry.from(
    EntryMeta meta, {
    required int recentUseAt,
    required int position,
  }) {
    final title = meta.title.toLowerCase();
    final titlePinyin = _Pinyin.full(meta.title);
    final titleInitials = _Pinyin.short(meta.title);
    final otherParts = [
      meta.username,
      meta.url,
      ...meta.tags,
    ].map((part) => part.toLowerCase()).toList(growable: false);
    final otherPinyin = [
      meta.username,
      meta.url,
      ...meta.tags,
    ].expand(
      (part) => [_Pinyin.full(part), _Pinyin.short(part)],
    );
    final otherBlob = [...otherParts, ...otherPinyin].join(' ');
    final searchBlob = [
      title,
      titlePinyin,
      titleInitials,
      otherBlob,
    ].join(' ');

    return _IndexedEntry(
      meta: meta,
      recentUseAt: recentUseAt,
      position: position,
      title: title,
      titlePinyin: titlePinyin,
      titleInitials: titleInitials,
      otherBlob: otherBlob,
      searchBlob: searchBlob,
    );
  }

  int? rank(List<String> tokens) {
    var worstRank = 0;
    for (final token in tokens) {
      final tokenRank = _rankToken(token);
      if (tokenRank == null) return null;
      if (tokenRank > worstRank) worstRank = tokenRank;
    }
    return worstRank;
  }

  int? _rankToken(String token) {
    if (title.startsWith(token) ||
        titlePinyin.startsWith(token) ||
        titleInitials.startsWith(token)) {
      return 0;
    }
    if (title.contains(token) ||
        titlePinyin.contains(token) ||
        titleInitials.contains(token)) {
      return 1;
    }
    if (otherBlob.contains(token) || searchBlob.contains(token)) {
      return 2;
    }
    return null;
  }

  /// 标题通过拼音全拼或首字母命中，而非字面汉字命中时为真。
  bool isPinyinTitleMatch(List<String> tokens) {
    for (final token in tokens) {
      final pinyinHit =
          titlePinyin.contains(token) || titleInitials.contains(token);
      if (pinyinHit && !title.contains(token)) return true;
    }
    return false;
  }
}

class _Pinyin {
  static final Map<String, String> _fullCache = {};
  static final Map<String, String> _shortCache = {};
  static final RegExp _cjk = RegExp(r'[\u3400-\u9fff]');

  static String full(String value) {
    final lower = value.toLowerCase();
    if (!_cjk.hasMatch(value)) return lower;
    return _fullCache.putIfAbsent(
      value,
      () => PinyinHelper.getPinyinE(
        value,
        separator: '',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase(),
    );
  }

  static String short(String value) {
    final lower = value.toLowerCase();
    if (!_cjk.hasMatch(value)) return lower;
    return _shortCache.putIfAbsent(
      value,
      () => PinyinHelper.getShortPinyin(value).toLowerCase(),
    );
  }
}
