import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/shortcuts.dart';
import '../../services/vault_service.dart';
import '../detail/entry_detail_panel.dart';
import '../list/entry_filter.dart';
import '../list/entry_list_panel.dart';
import '../list/list_providers.dart';
import '../settings/settings_page.dart';
import '../unlock/unlock_page.dart';

/// 主界面 Shell（T2.7 / T2.11）：桌面三栏布局，窄屏折叠侧边栏，挂载全局快捷键。
class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  static const path = '/main';
  static const _compactBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: appShortcuts(),
      child: Actions(
        actions: buildAppActions(ref, context),
        // autofocus 让无控件聚焦时按键也能命中全局快捷键。
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactBreakpoint;
              final colorScheme = Theme.of(context).colorScheme;

              return Scaffold(
                backgroundColor: colorScheme.surface,
                appBar: compact ? const _CompactAppBar() : null,
                drawer: compact
                    ? Drawer(
                        width: 140,
                        child: _VaultSidebar(
                          colorScheme: colorScheme,
                          inDrawer: true,
                        ),
                      )
                    : null,
                body: SafeArea(
                  top: !compact,
                  child: Row(
                    children: [
                      if (!compact) _VaultSidebar(colorScheme: colorScheme),
                      const EntryListPanel(),
                      const Expanded(child: EntryDetailPanel()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompactAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CompactAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('PwVault'),
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '打开导航',
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.go(SettingsPage.path),
        ),
        IconButton(
          tooltip: '锁定',
          icon: const Icon(Icons.lock_outline),
          onPressed: () => context.go(UnlockPage.path),
        ),
      ],
    );
  }
}

class _VaultSidebar extends ConsumerWidget {
  const _VaultSidebar({required this.colorScheme, this.inDrawer = false});

  final ColorScheme colorScheme;
  final bool inDrawer;

  /// 选择过滤：切换视图、清空选中项，抽屉内点击后顺手收起抽屉。
  void _choose(BuildContext context, WidgetRef ref, EntryFilter filter) {
    ref.read(entryFilterProvider.notifier).set(filter);
    ref.read(selectedEntryIdProvider.notifier).select(null);
    if (inDrawer) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(entryFilterProvider);
    final allCount = ref.watch(entryListProvider).length;
    final favCount = ref.watch(entryListProvider).where((e) => e.favorite).length;
    final trashCount = ref.watch(trashListProvider).asData?.value.length ?? 0;
    final tags = ref.watch(allTagsProvider);

    return SizedBox(
      key: const ValueKey('vault-sidebar'),
      width: 140,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('保险库'),
              _NavRow(
                icon: Icons.list_alt_outlined,
                label: '全部条目',
                count: '$allCount',
                selected: filter is AllEntriesFilter,
                colorScheme: colorScheme,
                onTap: () => _choose(context, ref, const AllEntriesFilter()),
              ),
              _NavRow(
                icon: Icons.star_border_outlined,
                label: '常用',
                count: favCount == 0 ? null : '$favCount',
                selected: filter is FavoritesFilter,
                colorScheme: colorScheme,
                onTap: () => _choose(context, ref, const FavoritesFilter()),
              ),
              _NavRow(
                icon: Icons.delete_outline,
                label: '回收站',
                count: trashCount == 0 ? null : '$trashCount',
                selected: filter is TrashFilter,
                colorScheme: colorScheme,
                onTap: () => _choose(context, ref, const TrashFilter()),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionLabel('标签'),
                for (final tag in tags)
                  _TagRow(
                    label: tag,
                    color: _tagColor(tag),
                    selected: filter is TagFilter && filter.tag == tag,
                    onTap: () => _choose(context, ref, TagFilter(tag)),
                  ),
              ],
              const Spacer(),
              Divider(color: colorScheme.outlineVariant, height: 20),
              _NavRow(
                icon: Icons.settings_outlined,
                label: '设置',
                colorScheme: colorScheme,
                onTap: () => context.go(SettingsPage.path),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.colorScheme,
    this.count,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  count!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.label,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标签圆点取色，按标签名稳定取一档。
Color _tagColor(String tag) {
  const palette = <Color>[
    Color(0xFF1D9E75),
    Color(0xFF7F77DD),
    Color(0xFFD85A30),
    Color(0xFF2E7BC4),
    Color(0xFFB0851F),
  ];
  return palette[tag.hashCode.abs() % palette.length];
}
