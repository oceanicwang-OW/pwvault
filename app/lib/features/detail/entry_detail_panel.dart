import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/avatar.dart';
import '../../services/clipboard_service.dart';
import '../../services/vault_service.dart';
import '../edit/entry_edit_form.dart';
import '../list/entry_filter.dart';
import '../list/list_providers.dart';
import 'field_row.dart';
import 'password_field_row.dart';

/// 详情面板（T2.9 / 真实化）：展示左侧选中的条目，密码走单条目按需解密，
/// 复制反馈倒计时条；未选中时显示空态。
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

  Future<void> _copyPassword(String password) async {
    final clearAfter = ref.read(clipboardClearAfterProvider);
    await ref.read(clipboardServiceProvider).copyPassword(password);
    if (!mounted) return; // 复制 await 期间可能因自动锁定/导航卸载
    _startFeedback(clearAfter);
  }

  Future<void> _copyUsername(String username) async {
    await Clipboard.setData(ClipboardData(text: username));
  }

  Future<void> _delete(EntryMeta meta) async {
    ref.read(selectedEntryIdProvider.notifier).select(null);
    await ref.read(vaultProvider.notifier).softDelete(meta.id);
  }

  Future<void> _restore(EntryMeta meta) async {
    ref.read(selectedEntryIdProvider.notifier).select(null);
    await ref.read(vaultProvider.notifier).restore(meta.id);
  }

  /// 切换常用：取完整条目 → 翻转 favorite → 写回（真实 CRUD 更新）。
  Future<void> _toggleFavorite(EntryMeta meta) async {
    final notifier = ref.read(vaultProvider.notifier);
    final full = await notifier.getFull(meta.id);
    await notifier.upsert(
      EntryDraft(
        id: meta.id,
        title: full.title,
        username: full.username,
        password: full.password,
        url: full.url,
        notes: full.notes,
        totpUri: full.totpUri,
        tags: full.tags,
        favorite: !full.favorite,
      ),
    );
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
    final selectedId = ref.watch(selectedEntryIdProvider);
    final entries = ref.watch(viewEntriesProvider);
    final inTrash = ref.watch(entryFilterProvider) is TrashFilter;
    final meta = _findById(entries, selectedId);

    return DecoratedBox(
      key: const ValueKey('entry-detail-column'),
      decoration: BoxDecoration(color: colorScheme.surface),
      child: meta == null
          ? _EmptyDetail(colorScheme: colorScheme)
          : _content(context, colorScheme, meta, inTrash: inTrash),
    );
  }

  Widget _content(
    BuildContext context,
    ColorScheme colorScheme,
    EntryMeta meta, {
    required bool inTrash,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, colorScheme, meta, inTrash: inTrash),
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
                  value: Text(meta.username.isEmpty ? '—' : meta.username),
                  actions: [
                    IconButton(
                      tooltip: '用户名 复制',
                      onPressed: meta.username.isEmpty
                          ? null
                          : () => _copyUsername(meta.username),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                PasswordFieldRow(
                  key: ValueKey('pw-${meta.id}'),
                  label: '密码',
                  revealPassword: () =>
                      ref.read(vaultProvider.notifier).revealPassword(meta.id),
                  onCopy: _copyPassword,
                ),
                FieldRow(
                  label: '网址',
                  value: Text(
                    meta.url.isEmpty ? '—' : meta.url,
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
                FieldRow(
                  label: '标签',
                  isLast: true,
                  value: meta.tags.isEmpty
                      ? const Text('—')
                      : Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in meta.tags)
                              _TagChip(label: tag, colorScheme: colorScheme),
                          ],
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
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme colorScheme,
    EntryMeta meta, {
    required bool inTrash,
  }) {
    return Row(
      children: [
        EntryAvatar(
          id: meta.id,
          initial: meta.title.characters.first,
          size: 40,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meta.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                _formatUpdated(meta.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (inTrash)
          IconButton(
            tooltip: '恢复',
            onPressed: () => _restore(meta),
            icon: const Icon(Icons.restore_from_trash_outlined),
          )
        else ...[
          IconButton(
            tooltip: '编辑',
            onPressed: () => showEntryEditDialog(context, initial: meta),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: meta.favorite ? '取消常用' : '设为常用',
            onPressed: () => _toggleFavorite(meta),
            icon: Icon(
              meta.favorite ? Icons.star : Icons.star_border_outlined,
              color: meta.favorite ? colorScheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: '删除（移到回收站）',
            onPressed: () => _delete(meta),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
    );
  }
}

/// 把 [int] 毫秒时间戳格式化为相对“修改于”文案。
String _formatUpdated(int ms) {
  if (ms <= 0) return '最近更新';
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 0) return '最近更新';
  final minutes = diff ~/ 60000;
  if (minutes < 1) return '刚刚更新';
  if (minutes < 60) return '$minutes 分钟前更新';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours 小时前更新';
  return '${hours ~/ 24} 天前更新';
}

EntryMeta? _findById(List<EntryMeta> entries, String? id) {
  if (id == null) return null;
  for (final e in entries) {
    if (e.id == id) return e;
  }
  return null;
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            '从左侧选择一个条目查看详情',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.colorScheme});

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
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
