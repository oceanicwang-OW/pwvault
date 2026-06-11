import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/main.dart';

void main() {
  testWidgets('启动进入解锁页，占位解锁可进入主界面', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PwVaultApp()));
    expect(find.text('保险库已锁定'), findsOneWidget);

    await tester.tap(find.text('解锁（占位）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('主界面'), findsOneWidget);
  });
}
