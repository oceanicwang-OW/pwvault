import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/main.dart';

void main() {
  testWidgets('启动进入静态解锁页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PwVaultApp()));

    expect(find.text('PwVault'), findsOneWidget);
    expect(find.text('保险库已锁定'), findsOneWidget);
    expect(find.text('个人库 · vault.pwvault'), findsOneWidget);
    expect(find.text('连续输错 5 次将强制等待'), findsOneWidget);
    expect(find.text('解锁（占位）'), findsNothing);
  });
}
