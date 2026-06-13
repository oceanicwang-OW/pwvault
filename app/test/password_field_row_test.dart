import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/detail/password_field_row.dart';

const _plain = 'secret-pw';
const _masked = '••••••••';

void main() {
  Future<void> pumpRow(WidgetTester tester, {List<String>? copied}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordFieldRow(
            label: '密码',
            revealPassword: () async => _plain,
            onCopy: (value) async => copied?.add(value),
          ),
        ),
      ),
    );
  }

  Future<void> tapReveal(WidgetTester tester) async {
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump(); // 解析 revealPassword 的微任务
    await tester.pump();
  }

  testWidgets('starts masked with 8 dots and no plaintext', (tester) async {
    await pumpRow(tester);

    expect(find.text(_masked), findsOneWidget);
    expect(find.text(_plain), findsNothing);
  });

  testWidgets('eye reveals plaintext with a 10s countdown', (tester) async {
    await pumpRow(tester);
    await tapReveal(tester);

    expect(find.text(_plain), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    expect(find.text(_masked), findsNothing);

    // 收尾：回隐以取消倒计时
    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
  });

  testWidgets('clicking the eye again hides plaintext', (tester) async {
    await pumpRow(tester);
    await tapReveal(tester);
    expect(find.text(_plain), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();

    expect(find.text(_plain), findsNothing);
    expect(find.text(_masked), findsOneWidget);
  });

  testWidgets('countdown reaching zero auto-hides plaintext', (tester) async {
    await pumpRow(tester);
    await tapReveal(tester);
    expect(find.text(_plain), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text(_plain), findsNothing);
    expect(find.text(_masked), findsOneWidget);
  });

  testWidgets('counts down each second', (tester) async {
    await pumpRow(tester);
    await tapReveal(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('9s'), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
  });

  testWidgets('backgrounding the app immediately hides plaintext', (
    tester,
  ) async {
    await pumpRow(tester);
    await tapReveal(tester);
    expect(find.text(_plain), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.text(_plain), findsNothing);
    expect(find.text(_masked), findsOneWidget);
  });

  testWidgets('copy from masked state still yields the plaintext', (
    tester,
  ) async {
    final copied = <String>[];
    await pumpRow(tester, copied: copied);

    await tester.tap(find.byTooltip('复制密码'));
    await tester.pump();
    await tester.pump();

    expect(copied, [_plain]);
    // 复制不应解除掩码
    expect(find.text(_masked), findsOneWidget);
    expect(find.text(_plain), findsNothing);
  });
}
