import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../unlock/unlock_page.dart';

/// 主界面 Shell（T2.7）：桌面三栏布局，窄屏折叠侧边栏。
class MainPage extends StatelessWidget {
  const MainPage({super.key});

  static const path = '/main';
  static const _compactBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: compact ? const _CompactAppBar() : null,
          drawer: compact
              ? Drawer(
                  width: 140,
                  child: _VaultSidebar(colorScheme: colorScheme),
                )
              : null,
          body: SafeArea(
            top: !compact,
            child: Row(
              children: [
                if (!compact) _VaultSidebar(colorScheme: colorScheme),
                _EntryListColumn(colorScheme: colorScheme),
                const Expanded(child: _EntryDetailColumn()),
              ],
            ),
          ),
        );
      },
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
          tooltip: '锁定',
          icon: const Icon(Icons.lock_outline),
          onPressed: () => context.go(UnlockPage.path),
        ),
      ],
    );
  }
}

class _VaultSidebar extends StatelessWidget {
  const _VaultSidebar({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
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
                count: '128',
                selected: true,
                colorScheme: colorScheme,
              ),
              _NavRow(
                icon: Icons.star_border_outlined,
                label: '常用',
                colorScheme: colorScheme,
              ),
              _NavRow(
                icon: Icons.delete_outline,
                label: '回收站',
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 12),
              const _SectionLabel('标签'),
              _TagRow(label: '工作', color: const Color(0xFF1D9E75)),
              _TagRow(label: '个人', color: const Color(0xFF7F77DD)),
              _TagRow(label: '金融', color: const Color(0xFFD85A30)),
              const Spacer(),
              Divider(color: colorScheme.outlineVariant, height: 20),
              _NavRow(
                icon: Icons.settings_outlined,
                label: '设置',
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryListColumn extends StatelessWidget {
  const _EntryListColumn({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'tb',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 1,
                              height: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: '新建条目',
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(
                  '拼音匹配 · 2 条结果',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            _EntryTile(
              initial: '淘',
              title: '淘宝',
              subtitle: 'owen_dev@163.com',
              selected: true,
              background: const Color(0xFFFAECE7),
              foreground: const Color(0xFF712B13),
              colorScheme: colorScheme,
            ),
            _EntryTile(
              initial: '天',
              title: '天猫超市',
              subtitle: '138****2046',
              background: const Color(0xFFE1F5EE),
              foreground: const Color(0xFF085041),
              colorScheme: colorScheme,
            ),
            const Spacer(),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryDetailColumn extends StatelessWidget {
  const _EntryDetailColumn();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      key: const ValueKey('entry-detail-column'),
      decoration: BoxDecoration(color: colorScheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Avatar(
                  initial: '淘',
                  size: 40,
                  background: Color(0xFFFAECE7),
                  foreground: Color(0xFF712B13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '淘宝',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '修改于 3 天前',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '编辑',
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '常用',
                  onPressed: () {},
                  icon: const Icon(Icons.star_border_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  _FieldRow(
                    label: '用户名',
                    value: 'owen_dev@163.com',
                    trailingIcon: Icons.copy_outlined,
                  ),
                  _FieldRow(
                    label: '密码',
                    value: '••••••••',
                    sensitive: true,
                    trailingIcon: Icons.visibility_outlined,
                    secondaryTrailingIcon: Icons.copy_outlined,
                  ),
                  _FieldRow(
                    label: '网址',
                    value: 'taobao.com',
                    isLink: true,
                    trailingIcon: Icons.open_in_new,
                  ),
                  _FieldRow(label: '标签', tagValue: '个人', isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.content_paste_outlined,
                      size: 16,
                      color: colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '密码已复制，23 秒后自动清空剪贴板',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 60,
                      child: LinearProgressIndicator(
                        value: 0.7,
                        minHeight: 4,
                        color: colorScheme.onTertiaryContainer,
                        backgroundColor: colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
  });

  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
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
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.initial,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.foreground,
    required this.colorScheme,
    this.selected = false,
  });

  final String initial;
  final String title;
  final String subtitle;
  final Color background;
  final Color foreground;
  final ColorScheme colorScheme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _Avatar(
            initial: initial,
            size: 32,
            background: background,
            foreground: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? colorScheme.onPrimaryContainer : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
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
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.size,
    required this.background,
    required this.foreground,
  });

  final String initial;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    this.value,
    this.isLink = false,
    this.trailingIcon,
    this.secondaryTrailingIcon,
    this.sensitive = false,
    this.tagValue,
    this.isLast = false,
  });

  final String label;
  final String? value;
  final bool isLink;
  final IconData? trailingIcon;
  final IconData? secondaryTrailingIcon;
  final bool sensitive;
  final String? tagValue;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: sensitive ? colorScheme.surfaceContainerHighest : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: tagValue == null
                  ? Text(
                      value ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLink ? colorScheme.primary : null,
                        letterSpacing: sensitive ? 2 : 0,
                        fontFamily: sensitive ? 'monospace' : null,
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tagValue!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ),
            ),
            if (trailingIcon != null)
              IconButton(
                tooltip: label,
                onPressed: () {},
                icon: Icon(trailingIcon, size: 18),
              ),
            if (secondaryTrailingIcon != null)
              IconButton(
                tooltip: '$label 复制',
                onPressed: () {},
                icon: Icon(secondaryTrailingIcon, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
