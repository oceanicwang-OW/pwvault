import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../services/autolock_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/local_config.dart';
import '../shell/main_page.dart';
import 'change_password_section.dart';

/// 设置页（T2.12）：主题、自动锁定时长、剪贴板清除时长、修改主密码。
///
/// 时长/主题接通既有内存 provider，当前会话即时生效；落盘持久化留待后续
/// 任务（需引入本地存储，与库内 meta 协调）。修改主密码见
/// [ChangePasswordSection]：成功后立即锁定并退回解锁页。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const path = '/settings';

  /// 自动锁定可选时长（PDR 未钉死具体档位，取常用安全档）。
  static const autoLockOptions = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  /// 剪贴板清除可选时长。
  static const clipboardOptions = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(MainPage.path),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _ThemeSection(),
                  SizedBox(height: 16),
                  _SecuritySection(),
                  SizedBox(height: 16),
                  ChangePasswordSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组卡片：标题 + 内容，复用解锁页的容器视觉。
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 带说明文字的设置行：左侧标签+副标题，右侧控件。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.control,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return SettingsCard(
      title: '外观',
      children: [
        SettingsRow(
          label: '主题',
          subtitle: '跟随系统或手动指定亮/暗',
          control: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {mode},
            onSelectionChanged: (selection) {
              final next = selection.first;
              ref.read(themeModeProvider.notifier).set(next);
              unawaited(
                ref.read(appConfigProvider.notifier).setThemeMode(next.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoLock = ref.watch(autoLockTimeoutProvider);
    final clipboard = ref.watch(clipboardClearAfterProvider);

    return SettingsCard(
      title: '安全',
      children: [
        SettingsRow(
          label: '自动锁定',
          subtitle: '空闲超过该时长后锁定保险库',
          control: DropdownButton<Duration>(
            value: autoLock,
            onChanged: (value) {
              if (value != null) {
                ref.read(autoLockTimeoutProvider.notifier).setTimeout(value);
                unawaited(
                  ref
                      .read(appConfigProvider.notifier)
                      .setAutoLockSeconds(value.inSeconds),
                );
              }
            },
            items: [
              for (final d in SettingsPage.autoLockOptions)
                DropdownMenuItem(value: d, child: Text(_formatMinutes(d))),
            ],
          ),
        ),
        SettingsRow(
          label: '剪贴板清除',
          subtitle: '复制密码后自动清空剪贴板的延时',
          control: DropdownButton<Duration>(
            value: clipboard,
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(clipboardClearAfterProvider.notifier)
                    .setClearAfter(value);
                unawaited(
                  ref
                      .read(appConfigProvider.notifier)
                      .setClipboardSeconds(value.inSeconds),
                );
              }
            },
            items: [
              for (final d in SettingsPage.clipboardOptions)
                DropdownMenuItem(value: d, child: Text(_formatSeconds(d))),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatMinutes(Duration d) => '${d.inMinutes} 分钟';

String _formatSeconds(Duration d) => '${d.inSeconds} 秒';
