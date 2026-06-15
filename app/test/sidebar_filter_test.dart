import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/shell/main_page.dart';
import 'package:pwvault/services/vault_service.dart';

import 'support/fake_vault.dart';

EntryDraft _draft(
  String id,
  String title, {
  List<String> tags = const [],
  bool favorite = false,
}) => EntryDraft(
  id: id,
  title: title,
  username: '$id@x',
  password: 'pw-$id',
  url: '$id.com',
  notes: '',
  tags: tags,
  favorite: favorite,
);

final _seeds = [
  _draft('alpha', '阿尔法', tags: ['工作'], favorite: true),
  _draft('beta', '贝塔', tags: ['个人']),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultBackendProvider.overrideWithValue(FakeVaultBackend(_seeds)),
      ],
      child: const MaterialApp(home: MainPage()),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MainPage)),
  );
  await container.read(vaultProvider.notifier).unlock('p', 'pw');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('favorites filter shows only favorite entries', (tester) async {
    await _pump(tester);
    expect(find.text('全部条目 · 2 条'), findsOneWidget);

    await tester.tap(find.text('常用'));
    await tester.pumpAndSettle();

    expect(find.text('常用 · 1 条'), findsOneWidget);
    expect(find.text('阿尔法'), findsOneWidget);
    expect(find.text('贝塔'), findsNothing);
  });

  testWidgets('tag filter shows only entries with that tag', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();

    expect(find.text('标签 个人 · 1 条'), findsOneWidget);
    expect(find.text('贝塔'), findsOneWidget);
    expect(find.text('阿尔法'), findsNothing);
  });

  testWidgets('delete moves an entry to trash; restore brings it back', (
    tester,
  ) async {
    await _pump(tester);

    // 选中阿尔法 → 删除（移到回收站）
    await tester.tap(find.text('阿尔法'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除（移到回收站）'));
    await tester.pumpAndSettle();

    expect(find.text('全部条目 · 1 条'), findsOneWidget);
    expect(find.text('阿尔法'), findsNothing);

    // 回收站里能找到它，计数为 1
    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();
    expect(find.text('回收站 · 1 条'), findsOneWidget);
    expect(find.text('阿尔法'), findsOneWidget);

    // 恢复 → 回收站清空
    await tester.tap(find.text('阿尔法'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('回收站为空'), findsOneWidget);

    // 回到全部条目应重新出现
    await tester.tap(find.text('全部条目'));
    await tester.pumpAndSettle();
    expect(find.text('全部条目 · 2 条'), findsOneWidget);
    expect(find.text('阿尔法'), findsOneWidget);
  });
}
