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
