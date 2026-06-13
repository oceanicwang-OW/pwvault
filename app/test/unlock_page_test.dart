import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/main.dart';

void main() {
  testWidgets('renders the static vault unlock form', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PwVaultApp()));

    expect(find.text('PwVault'), findsOneWidget);
    expect(find.text('保险库已锁定'), findsOneWidget);
    expect(find.text('个人库 · vault.pwvault'), findsOneWidget);
    expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.text('连续输错 5 次将强制等待'), findsOneWidget);
    expect(find.text('解锁（占位）'), findsNothing);
  });

  testWidgets('toggles password visibility locally', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PwVaultApp()));

    TextField passwordField() =>
        tester.widget<TextField>(find.byType(TextField));

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
