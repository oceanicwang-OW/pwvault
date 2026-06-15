import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pwvault/features/list/list_providers.dart';
import 'package:pwvault/features/shell/main_page.dart';
import 'package:pwvault/features/unlock/unlock_page.dart';
import 'package:pwvault/services/clipboard_service.dart';
import 'package:pwvault/services/vault_service.dart';

import 'support/fake_vault.dart';

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

void main() {
  late _FakeClipboardGateway gateway;

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    gateway = _FakeClipboardGateway();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final router = GoRouter(
      initialLocation: MainPage.path,
      routes: [
        GoRoute(path: MainPage.path, builder: (_, _) => const MainPage()),
        GoRoute(
          path: UnlockPage.path,
          builder: (_, _) => const Scaffold(body: Text('UNLOCK-PAGE')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clipboardGatewayProvider.overrideWithValue(gateway),
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainPage)),
    );
    await container.read(vaultProvider.notifier).unlock('p', 'pw');
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+F focuses the search field', (tester) async {
    final container = await pumpApp(tester);
    expect(container.read(listSearchFocusProvider).hasFocus, isFalse);

    await sendCtrl(tester, LogicalKeyboardKey.keyF);

    expect(container.read(listSearchFocusProvider).hasFocus, isTrue);
  });

  testWidgets('Ctrl+L locks (navigates to the unlock route)', (tester) async {
    await pumpApp(tester);

    await sendCtrl(tester, LogicalKeyboardKey.keyL);

    expect(find.text('UNLOCK-PAGE'), findsOneWidget);
  });

  testWidgets('Ctrl+N opens the new-entry dialog', (tester) async {
    await pumpApp(tester);

    await sendCtrl(tester, LogicalKeyboardKey.keyN);

    expect(find.text('新建条目'), findsOneWidget);
  });

  testWidgets('Arrow keys move the selection within visible results', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    expect(container.read(selectedEntryIdProvider), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(container.read(selectedEntryIdProvider), 'taobao');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(container.read(selectedEntryIdProvider), 'tmall');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(container.read(selectedEntryIdProvider), 'taobao');
  });

  testWidgets('Enter copies the selected entry password', (tester) async {
    final container = await pumpApp(tester);
    container.read(selectedEntryIdProvider.notifier).select('taobao');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(gateway.writes, contains(demoPasswordFor('taobao')));
  });
}
