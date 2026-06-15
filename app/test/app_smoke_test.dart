import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/unlock/vault_location.dart';
import 'package:pwvault/main.dart';

void main() {
  testWidgets('启动进入解锁页（库已存在）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultLocationProvider.overrideWith(
            (ref) async =>
                const VaultLocation(path: 'dir/vault.pwvault', exists: true),
          ),
        ],
        child: const PwVaultApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PwVault'), findsOneWidget);
    expect(find.text('保险库已锁定'), findsOneWidget);
    expect(find.text('vault.pwvault'), findsOneWidget);
    expect(find.text('连续输错 5 次将强制等待'), findsOneWidget);
  });
}
