import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/detail/entry_detail_panel.dart';
import 'package:pwvault/services/clipboard_service.dart';

const _mockPassword = 'Tb#2024_demo!';
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

void main() {
  Future<_FakeClipboardGateway> pumpPanel(WidgetTester tester) async {
    final gateway = _FakeClipboardGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clipboardGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: Scaffold(body: EntryDetailPanel())),
      ),
    );
    return gateway;
  }

  testWidgets('password masked and no copy feedback by default', (
    tester,
  ) async {
    await pumpPanel(tester);

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

    expect(gateway.writes, [_mockPassword]);
    expect(find.text('密码已复制，30 秒后自动清空剪贴板'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('密码已复制，29 秒后自动清空剪贴板'), findsOneWidget);
  });

  testWidgets('eye button reveals the mock password', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_mockPassword), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
  });
}
