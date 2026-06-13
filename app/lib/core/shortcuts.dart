import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/edit/entry_edit_form.dart';
import '../features/list/list_providers.dart';
import '../features/list/mock_entry_store.dart';
import '../features/unlock/unlock_page.dart';
import '../services/clipboard_service.dart';

/// 全局快捷键（T2.11）：Ctrl/Cmd+F 聚焦搜索、Ctrl/Cmd+L 锁定、Ctrl/Cmd+N 新建、
/// Enter 复制选中条目密码、↑↓ 列表导航。

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class LockVaultIntent extends Intent {
  const LockVaultIntent();
}

class NewEntryIntent extends Intent {
  const NewEntryIntent();
}

class CopyPasswordIntent extends Intent {
  const CopyPasswordIntent();
}

class MoveSelectionIntent extends Intent {
  const MoveSelectionIntent(this.delta);

  final int delta;
}

/// 键位映射；同时绑定 Control 与 Meta，覆盖 Windows/Linux 与 macOS。
Map<ShortcutActivator, Intent> appShortcuts() => const {
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, meta: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyL, control: true): LockVaultIntent(),
  SingleActivator(LogicalKeyboardKey.keyL, meta: true): LockVaultIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, control: true): NewEntryIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, meta: true): NewEntryIntent(),
  SingleActivator(LogicalKeyboardKey.enter): CopyPasswordIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp): MoveSelectionIntent(-1),
  SingleActivator(LogicalKeyboardKey.arrowDown): MoveSelectionIntent(1),
};

/// 在 [context]（含 GoRouter 与 ProviderScope）下构造快捷键对应的 Action 集合。
Map<Type, Action<Intent>> buildAppActions(WidgetRef ref, BuildContext context) {
  final searchFocus = ref.read(listSearchFocusProvider);
  return <Type, Action<Intent>>{
    FocusSearchIntent: CallbackAction<FocusSearchIntent>(
      onInvoke: (_) {
        searchFocus.requestFocus();
        return null;
      },
    ),
    LockVaultIntent: CallbackAction<LockVaultIntent>(
      onInvoke: (_) {
        context.go(UnlockPage.path);
        return null;
      },
    ),
    NewEntryIntent: CallbackAction<NewEntryIntent>(
      onInvoke: (_) {
        showEntryEditDialog(context);
        return null;
      },
    ),
    CopyPasswordIntent: _CopyPasswordAction(ref, searchFocus),
    MoveSelectionIntent: _MoveSelectionAction(ref, searchFocus),
  };
}

/// Enter 复制选中条目密码；搜索框聚焦时禁用，让 Enter 落回文本框。
class _CopyPasswordAction extends Action<CopyPasswordIntent> {
  _CopyPasswordAction(this.ref, this.searchFocus);

  final WidgetRef ref;
  final FocusNode searchFocus;

  @override
  bool get isActionEnabled => !searchFocus.hasFocus;

  @override
  Object? invoke(CopyPasswordIntent intent) {
    final id = ref.read(selectedEntryIdProvider);
    if (id == null) return null;
    ref.read(clipboardServiceProvider).copyPassword(mockPasswordFor(id));
    return null;
  }
}

/// ↑↓ 在当前可见结果内移动选中项；搜索框聚焦时禁用。
class _MoveSelectionAction extends Action<MoveSelectionIntent> {
  _MoveSelectionAction(this.ref, this.searchFocus);

  final WidgetRef ref;
  final FocusNode searchFocus;

  @override
  bool get isActionEnabled => !searchFocus.hasFocus;

  @override
  Object? invoke(MoveSelectionIntent intent) {
    final entries = ref.read(searchOutcomeProvider).entries;
    if (entries.isEmpty) return null;
    final current = ref.read(selectedEntryIdProvider);
    final index = entries.indexWhere((e) => e.id == current);
    final next = index == -1
        ? (intent.delta > 0 ? 0 : entries.length - 1)
        : (index + intent.delta).clamp(0, entries.length - 1);
    ref.read(selectedEntryIdProvider.notifier).select(entries[next].id);
    return null;
  }
}
