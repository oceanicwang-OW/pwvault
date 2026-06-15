import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/list/entry_list_panel.dart';
import 'package:pwvault/services/vault_service.dart';

import 'support/fake_vault.dart';

void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultBackendProvider.overrideWithValue(FakeVaultBackend(demoSeeds())),
        ],
        child: const MaterialApp(home: Scaffold(body: EntryListPanel())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EntryListPanel)),
    );
    await container.read(vaultProvider.notifier).unlock('p', 'pw');
    await tester.pumpAndSettle();
  }

  group('highlightSpans', () {
    test('marks case-insensitive literal hits and leaves the rest', () {
      final spans = highlightSpans('GitHub', ['git']);
      expect(spans.map((s) => s.text).toList(), ['Git', 'Hub']);
      expect(spans.map((s) => s.hit).toList(), [true, false]);
    });

    test('without tokens the whole string is a single non-hit span', () {
      final spans = highlightSpans('淘宝', const []);
      expect(spans, hasLength(1));
      expect(spans.single.text, '淘宝');
      expect(spans.single.hit, isFalse);
    });

    test('merges repeated and adjacent hits', () {
      final spans = highlightSpans('abcabc', ['bc']);
      expect(spans.map((s) => '${s.text}:${s.hit}').toList(), [
        'a:false',
        'bc:true',
        'a:false',
        'bc:true',
      ]);
    });
  });

  group('EntryListPanel', () {
    testWidgets('shows all mock entries before any query', (tester) async {
      await pumpPanel(tester);

      expect(find.text('全部条目 · 6 条'), findsOneWidget);
      expect(find.text('淘宝'), findsOneWidget);
      expect(find.text('招商银行'), findsOneWidget);
    });

    testWidgets('filtering waits for the 150ms debounce', (tester) async {
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'github');
      await tester.pump(); // < debounce window: still unfiltered
      expect(find.text('京东'), findsOneWidget);
      expect(find.text('全部条目 · 6 条'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('京东'), findsNothing);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('1 条结果'), findsOneWidget);
    });

    testWidgets('pinyin-initials query is tagged as 拼音匹配', (tester) async {
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'tb');
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.text('拼音匹配 · 1 条结果'), findsOneWidget);
      expect(find.text('淘宝'), findsOneWidget);
      expect(find.text('京东'), findsNothing);
    });

    testWidgets('Esc clears the query and restores the full list', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'github');
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('京东'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.text('全部条目 · 6 条'), findsOneWidget);
      expect(find.text('京东'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('empty result shows the create-entry guidance', (tester) async {
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.text('无匹配结果'), findsOneWidget);
      expect(find.text('未找到匹配条目'), findsOneWidget);
      expect(find.text('新建「zzzzz」'), findsOneWidget);
    });
  });
}
