import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/list/list_providers.dart';
import 'package:pwvault/features/shell/main_page.dart';
import 'package:pwvault/services/vault_service.dart';

import 'support/fake_vault.dart';

void main() {
  Future<ProviderContainer> pumpMainPage(
    WidgetTester tester, {
    required Size surfaceSize,
  }) async {
    final view = tester.view;
    view.devicePixelRatio = 1;
    view.physicalSize = surfaceSize;
    addTearDown(() {
      view.resetDevicePixelRatio();
      view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainPage)),
    );
    await container.read(vaultProvider.notifier).unlock('p', 'pw');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('desktop shell renders fixed sidebar and list columns', (
    tester,
  ) async {
    final container = await pumpMainPage(
      tester,
      surfaceSize: const Size(1200, 800),
    );
    container.read(selectedEntryIdProvider.notifier).select('taobao');
    await tester.pumpAndSettle();

    expect(find.text('PwVault — 主界面（占位）'), findsNothing);
    expect(find.text('列表 / 详情三栏布局由 T2.7 实现'), findsNothing);

    expect(find.byKey(const ValueKey('vault-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-list-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-detail-column')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('vault-sidebar'))).width,
      140,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('entry-list-column'))).width,
      220,
    );

    expect(find.text('保险库'), findsOneWidget);
    expect(find.text('全部条目'), findsOneWidget);
    // 侧边栏「全部条目」计数为真实条目数（演示库 6 条）。
    expect(find.text('6'), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('标签'), findsWidgets);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('金融'), findsOneWidget);

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('全部条目 · 6 条'), findsOneWidget);
    expect(find.text('淘宝'), findsNWidgets(2));
    expect(find.text('天猫超市'), findsOneWidget);
    expect(find.text('5 分钟后自动锁定'), findsOneWidget);

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('网址'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);
  });

  testWidgets('narrow shell collapses sidebar into a hamburger drawer', (
    tester,
  ) async {
    await pumpMainPage(tester, surfaceSize: const Size(820, 700));

    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('entry-list-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-detail-column')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault-sidebar')), findsOneWidget);
    expect(find.text('全部条目'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
