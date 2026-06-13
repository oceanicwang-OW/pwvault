import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/search_index.dart';
import '../../services/vault_service.dart';
import '../edit/entry_edit_form.dart';
import 'mock_entry_store.dart';

/// 输入到过滤之间的防抖窗口（PDR 7.3：列表栏搜索 150ms debounce）。
const _debounce = Duration(milliseconds: 150);

/// 列表栏（T2.8 / T2.10）：搜索框（150ms debounce、Esc 清空）、命中高亮结果列表、
/// "拼音匹配"标注、空态引导新建；条目来自共享 [mockEntryStoreProvider]，
/// 新建/编辑保存后即时刷新。
class EntryListPanel extends ConsumerStatefulWidget {
  const EntryListPanel({super.key});

  @override
  ConsumerState<EntryListPanel> createState() => _EntryListPanelState();
}

class _EntryListPanelState extends ConsumerState<EntryListPanel> {
  final _controller = TextEditingController();
  final _searchFocus = FocusNode();

  Timer? _debounceTimer;
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _clearQuery() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = ref.watch(mockEntryStoreProvider);
    final outcome = SearchIndexService.fromEntries(
      entries,
    ).searchDetailed(_query);
    final tokens = SearchIndexService.tokenize(_query);

    return SizedBox(
      key: const ValueKey('entry-list-column'),
      width: 220,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          children: [
            _searchBar(colorScheme),
            _resultHeader(context, outcome),
            Expanded(
              child: outcome.entries.isEmpty
                  ? _EmptyResults(
                      query: _query,
                      onCreate: () => showEntryEditDialog(context),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: outcome.entries.length,
                      itemBuilder: (context, i) {
                        final meta = outcome.entries[i];
                        return _ResultTile(
                          meta: meta,
                          tokens: tokens,
                          selected: meta.id == _selectedId,
                          colorScheme: colorScheme,
                          onTap: () => setState(() => _selectedId = meta.id),
                        );
                      },
                    ),
            ),
            _autoLockFooter(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _clearQuery,
              },
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _controller,
                  focusNode: _searchFocus,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索条目',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _clearQuery,
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: '新建条目',
            onPressed: () => showEntryEditDialog(context),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _resultHeader(BuildContext context, SearchOutcome outcome) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = outcome.entries.length;
    final String label;
    if (_query.isEmpty) {
      label = '全部条目 · $count 条';
    } else if (count == 0) {
      label = '无匹配结果';
    } else if (outcome.pinyinMatched) {
      label = '拼音匹配 · $count 条结果';
    } else {
      label = '$count 条结果';
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _autoLockFooter(BuildContext context, ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.lock_clock_outlined,
              size: 15,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '5 分钟后自动锁定',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把 [text] 按 [tokens] 的子串命中切成命中/未命中片段，供结果标题高亮。
/// 大小写不敏感，多个 token 的命中区间会合并。
List<HighlightSpan> highlightSpans(String text, Iterable<String> tokens) {
  final lower = text.toLowerCase();
  final marked = List<bool>.filled(text.length, false);
  for (final raw in tokens) {
    final token = raw.toLowerCase().trim();
    if (token.isEmpty) continue;
    var start = lower.indexOf(token);
    while (start != -1) {
      for (var i = start; i < start + token.length; i++) {
        marked[i] = true;
      }
      start = lower.indexOf(token, start + token.length);
    }
  }

  final spans = <HighlightSpan>[];
  final buffer = StringBuffer();
  bool? current;
  for (var i = 0; i < text.length; i++) {
    if (current != null && marked[i] != current) {
      spans.add(HighlightSpan(buffer.toString(), hit: current));
      buffer.clear();
    }
    current = marked[i];
    buffer.write(text[i]);
  }
  if (buffer.isNotEmpty) {
    spans.add(HighlightSpan(buffer.toString(), hit: current ?? false));
  }
  return spans;
}

/// 高亮片段：[text] 是文本，[hit] 表示是否落在搜索命中区间内。
class HighlightSpan {
  final String text;
  final bool hit;

  const HighlightSpan(this.text, {required this.hit});
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.meta,
    required this.tokens,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  final EntryMeta meta;
  final List<String> tokens;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _avatarPalette(meta.id);
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: selected ? colorScheme.onPrimaryContainer : null,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Avatar(
              initial: meta.title.characters.first,
              background: palette.$1,
              foreground: palette.$2,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final span in highlightSpans(meta.title, tokens))
                          TextSpan(
                            text: span.text,
                            style: span.hit
                                ? TextStyle(
                                    backgroundColor:
                                        colorScheme.tertiaryContainer,
                                    color: colorScheme.onTertiaryContainer,
                                  )
                                : null,
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: baseStyle,
                  ),
                  Text(
                    meta.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query, required this.onCreate});

  final String query;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 36,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text('未找到匹配条目', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '换个关键词，或新建一条',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: Text(query.isEmpty ? '新建条目' : '新建「$query」'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.background,
    required this.foreground,
  });

  final String initial;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// mock 条目的色块底/字色，按 id 稳定取色。
(Color, Color) _avatarPalette(String id) {
  const palette = <(Color, Color)>[
    (Color(0xFFFAECE7), Color(0xFF712B13)),
    (Color(0xFFE1F5EE), Color(0xFF085041)),
    (Color(0xFFFBE9E7), Color(0xFFB0341A)),
    (Color(0xFFE8EAF6), Color(0xFF283593)),
    (Color(0xFFE3F2E9), Color(0xFF1B5E20)),
    (Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
  ];
  return palette[id.hashCode.abs() % palette.length];
}
