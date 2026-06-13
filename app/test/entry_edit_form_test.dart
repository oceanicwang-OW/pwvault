import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/edit/entry_edit_form.dart';
import 'package:pwvault/features/list/entry_list_panel.dart';
import 'package:pwvault/services/password_gen.dart';
import 'package:pwvault/services/vault_service.dart';

const _generated = 'GENERATED-PW-123';

class _FakeBackend implements PasswordGeneratorBackend {
  @override
  Future<String> generatePassword(PasswordGenerationOptions options) async =>
      _generated;

  @override
  Future<String> generatePassphrase({
    required int words,
    required String separator,
  }) async => 'alpha-bravo-charlie-delta';
}

Widget _host(Widget child) => ProviderScope(
  overrides: [
    passwordGeneratorBackendProvider.overrideWithValue(_FakeBackend()),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('blocks save and shows error when title is empty', (
    tester,
  ) async {
    EntryDraft? submitted;
    await tester.pumpWidget(
      _host(EntryEditForm(onSubmit: (d) => submitted = d, onCancel: () {})),
    );

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(submitted, isNull);
    expect(find.text('标题不能为空'), findsOneWidget);
  });

  testWidgets('valid save emits a draft with normalized url and tags', (
    tester,
  ) async {
    EntryDraft? submitted;
    await tester.pumpWidget(
      _host(EntryEditForm(onSubmit: (d) => submitted = d, onCancel: () {})),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '标题 *'), '我的银行');
    await tester.enterText(
      find.widgetWithText(TextFormField, '网址'),
      'mybank.com',
    );
    await tester.tap(find.widgetWithText(FilterChip, '金融'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.title, '我的银行');
    expect(submitted!.url, 'https://mybank.com');
    expect(submitted!.tags, contains('金融'));
  });

  testWidgets('cancel with no edits calls onCancel without confirming', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      _host(EntryEditForm(onSubmit: (_) {}, onCancel: () => cancelled = true)),
    );

    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(find.text('放弃未保存的更改？'), findsNothing);
  });

  testWidgets('dirty cancel confirms before discarding', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      _host(EntryEditForm(onSubmit: (_) {}, onCancel: () => cancelled = true)),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '标题 *'), '草稿');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的更改？'), findsOneWidget);
    expect(cancelled, isFalse);

    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });

  testWidgets('adopting a generated password fills the password field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(EntryEditForm(onSubmit: (_) {}, onCancel: () {})),
    );

    await tester.tap(find.byTooltip('生成密码'));
    await tester.pumpAndSettle(); // 打开弹层并完成首轮生成

    expect(find.text(_generated), findsOneWidget); // 弹层预览
    await tester.tap(find.text('采纳'));
    await tester.pumpAndSettle();

    // 回填后弹层关闭，密码字段显示生成结果
    expect(find.text(_generated), findsOneWidget);
  });

  testWidgets('saving a new entry refreshes the list (save→list)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const EntryListPanel()));

    expect(find.text('全部条目 · 6 条'), findsOneWidget);

    await tester.tap(find.byTooltip('新建条目'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '标题 *'), '新主机A');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新主机A'), findsOneWidget);
    expect(find.text('全部条目 · 7 条'), findsOneWidget);
  });
}
