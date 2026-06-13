import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/clipboard_service.dart';
import 'field_row.dart';
import 'password_field_row.dart';

// mock 条目（T2.10 接入真实选中条目与 entry_reveal_password 后替换）。
const _mockTitle = '淘宝';
const _mockInitial = '淘';
const _mockUsername = 'owen_dev@163.com';
const _mockUrl = 'taobao.com';
const _mockTag = '个人';
const _mockPassword = 'Tb#2024_demo!';

/// 详情面板（T2.9）：FieldRow 字段区、密码行状态机、复制反馈倒计时条。
class EntryDetailPanel extends ConsumerStatefulWidget {
  const EntryDetailPanel({super.key});

  @override
  ConsumerState<EntryDetailPanel> createState() => _EntryDetailPanelState();
}

class _EntryDetailPanelState extends ConsumerState<EntryDetailPanel> {
  Timer? _feedbackTimer;
  int _feedbackTotal = 0;
  int _feedbackRemaining = 0;

  bool get _showFeedback => _feedbackRemaining > 0;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<String> _revealPassword() async {
    // 对照 PDR 7.5：明文走单条目按需解密 entry_reveal_password（此处 mock）。
    return _mockPassword;
  }

  Future<void> _copyPassword(String password) async {
    final clearAfter = ref.read(clipboardClearAfterProvider);
    await ref.read(clipboardServiceProvider).copyPassword(password);
    if (!mounted) return; // 复制 await 期间可能因自动锁定/导航卸载
    _startFeedback(clearAfter);
  }

  void _startFeedback(Duration clearAfter) {
    _feedbackTimer?.cancel();
    final total = clearAfter.inSeconds;
    setState(() {
      _feedbackTotal = total;
      _feedbackRemaining = total;
    });
    _feedbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_feedbackRemaining <= 1) {
        _feedbackTimer?.cancel();
        _feedbackTimer = null;
        setState(() => _feedbackRemaining = 0);
      } else {
        setState(() => _feedbackRemaining -= 1);
      }
    });
  }

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
            _header(context, colorScheme),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  FieldRow(
                    label: '用户名',
                    value: const Text(_mockUsername),
                    actions: [
                      IconButton(
                        tooltip: '用户名 复制',
                        onPressed: () {},
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                    ],
                  ),
                  PasswordFieldRow(
                    label: '密码',
                    revealPassword: _revealPassword,
                    onCopy: _copyPassword,
                  ),
                  FieldRow(
                    label: '网址',
                    value: Text(
                      _mockUrl,
                      style: TextStyle(color: colorScheme.primary),
                    ),
                    actions: [
                      IconButton(
                        tooltip: '打开网址',
                        onPressed: () {},
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                    ],
                  ),
                  FieldRow(
                    label: '标签',
                    isLast: true,
                    value: Align(
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
                          _mockTag,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_showFeedback) ...[
              const SizedBox(height: 14),
              _CopyFeedbackBar(
                remaining: _feedbackRemaining,
                total: _feedbackTotal,
                colorScheme: colorScheme,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        const _Avatar(
          initial: _mockInitial,
          background: Color(0xFFFAECE7),
          foreground: Color(0xFF712B13),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mockTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    );
  }
}

class _CopyFeedbackBar extends StatelessWidget {
  const _CopyFeedbackBar({
    required this.remaining,
    required this.total,
    required this.colorScheme,
  });

  final int remaining;
  final int total;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                '密码已复制，$remaining 秒后自动清空剪贴板',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : remaining / total,
                minHeight: 4,
                color: colorScheme.onTertiaryContainer,
                backgroundColor: colorScheme.onTertiaryContainer.withValues(
                  alpha: 0.24,
                ),
              ),
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
      width: 40,
      height: 40,
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
