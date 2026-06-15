import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/detail/entry_detail_panel.dart';
import 'package:pwvault/features/list/list_providers.dart';
import 'package:pwvault/services/clipboard_service.dart';
import 'package:pwvault/services/vault_service.dart';

import 'support/fake_vault.dart';

final _password = demoPasswordFor('taobao');
const _masked = '••••••••';

class _FakeClipboardGateway implements ClipboardGateway {
  final List<String> writes = [];
  String? _current;

  @override
  Future<void> writeSensitiveText(String value) async {
    writes.add(value);
    _current = value;
  }

  @override
  Future<String?> readText() async => _current;
}

/// 让首次写入阻塞在 [gate] 上，以便把面板卸载精确落在 copyPassword 的 await 中。
class _BlockingClipboardGateway implements ClipboardGateway {
  final gate = Completer<void>();
  final List<String> writes = [];
  String? _current;
  var _blockedOnce = false;

  @override
  Future<void> writeSensitiveText(String value) async {
    if (!_blockedOnce) {
      _blockedOnce = true;
      await gate.future;
    }
    writes.add(value);
    _current = value;
  }

  @override
  Future<String?> readText() async => _current;
}

Future<void> _selectTaobao(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EntryDetailPanel)),
  );
  await container.read(vaultProvider.notifier).unlock('p', 'pw');
  container.read(selectedEntryIdProvider.notifier).select('taobao');
  await tester.pumpAndSettle();
}

void main() {
  Future<_FakeClipboardGateway> pumpPanel(WidgetTester tester) async {
    final gateway = _FakeClipboardGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clipboardGatewayProvider.overrideWithValue(gateway),
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: const MaterialApp(home: Scaffold(body: EntryDetailPanel())),
      ),
    );
    await _selectTaobao(tester);
    return gateway;
  }

  testWidgets('empty state when nothing is selected', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: const MaterialApp(home: Scaffold(body: EntryDetailPanel())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EntryDetailPanel)),
    );
    await container.read(vaultProvider.notifier).unlock('p', 'pw');
    await tester.pumpAndSettle();

    expect(find.text('从左侧选择一个条目查看详情'), findsOneWidget);
    expect(find.text(_masked), findsNothing);
  });

  testWidgets('selected entry shows its fields, masked password', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('淘宝'), findsOneWidget);
    expect(find.text('owen_dev@163.com'), findsOneWidget);
    expect(find.text('taobao.com'), findsOneWidget);
    expect(find.text(_masked), findsOneWidget);
    expect(find.textContaining('密码已复制'), findsNothing);
  });

  testWidgets('copy writes to clipboard and shows the countdown bar', (
    tester,
  ) async {
    final gateway = await pumpPanel(tester);

    await tester.tap(find.byTooltip('复制密码'));
    await tester.pump(); // reveal microtask
    await tester.pump(); // setState 反馈条

    expect(gateway.writes, [_password]);
    expect(find.text('密码已复制，30 秒后自动清空剪贴板'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('密码已复制，29 秒后自动清空剪贴板'), findsOneWidget);
  });

  testWidgets('eye button reveals the decrypted password', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_password), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
  });

  testWidgets('unmounting during the copy await does not setState after dispose', (
    tester,
  ) async {
    final gateway = _BlockingClipboardGateway();
    final show = ValueNotifier(true);
    addTearDown(show.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clipboardGatewayProvider.overrideWithValue(gateway),
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) =>
                  visible ? const EntryDetailPanel() : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await _selectTaobao(tester);

    await tester.tap(find.byTooltip('复制密码'));
    await tester.pump(); // 推进到 copyPassword 的写入 await，阻塞在 gate 上

    show.value = false; // 模拟自动锁定/导航：在 await 中卸载面板
    await tester.pump(); // 卸载面板，dispose State

    gateway.gate.complete(); // 放行写入，让复制的 await 继续
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(gateway.writes, [_password]);
  });
}
