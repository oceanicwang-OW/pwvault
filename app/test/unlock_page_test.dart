import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pwvault/features/shell/main_page.dart';
import 'package:pwvault/features/unlock/unlock_page.dart';
import 'package:pwvault/features/unlock/vault_location.dart';
import 'package:pwvault/services/vault_service.dart';

const _correct = 'right-master-pw';
const _strong = r'x7Km!q9Lp#vRt2Wz';

class _FakeSession implements VaultSession {
  @override
  Future<List<EntryMeta>> listMeta() async => const [];

  @override
  void dispose() {}

  @override
  Object noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeBackend implements VaultBackend {
  @override
  Future<VaultSession> create(String path, String password) async =>
      _FakeSession();

  @override
  Future<VaultSession> unlock(String path, String password) async {
    if (password != _correct) {
      throw const WrongPasswordException('WRONG_PASSWORD');
    }
    return _FakeSession();
  }
}

GoRouter _router() => GoRouter(
  initialLocation: UnlockPage.path,
  routes: [
    GoRoute(path: UnlockPage.path, builder: (_, _) => const UnlockPage()),
    GoRoute(
      path: MainPage.path,
      builder: (_, _) => const Scaffold(body: Text('MAIN-PLACEHOLDER')),
    ),
  ],
);

Widget _app({required bool exists, VaultBackend? backend}) => ProviderScope(
  overrides: [
    vaultLocationProvider.overrideWith(
      (ref) async => VaultLocation(path: 'dir/vault.pwvault', exists: exists),
    ),
    if (backend != null) vaultBackendProvider.overrideWithValue(backend),
  ],
  child: MaterialApp.router(routerConfig: _router()),
);

void main() {
  testWidgets('unlock mode renders for an existing vault', (tester) async {
    await tester.pumpWidget(_app(exists: true));
    await tester.pumpAndSettle();

    expect(find.text('保险库已锁定'), findsOneWidget);
    expect(find.text('vault.pwvault'), findsOneWidget);
    expect(find.text('连续输错 5 次将强制等待'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await tester.pumpWidget(_app(exists: true));
    await tester.pumpAndSettle();

    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('correct password unlocks and navigates to main', (tester) async {
    await tester.pumpWidget(_app(exists: true, backend: _FakeBackend()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), _correct);
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('MAIN-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('wrong password surfaces an error and stays', (tester) async {
    await tester.pumpWidget(_app(exists: true, backend: _FakeBackend()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('主密码不正确'), findsOneWidget);
    expect(find.text('MAIN-PLACEHOLDER'), findsNothing);
  });

  testWidgets('five wrong attempts trigger a lockout countdown', (
    tester,
  ) async {
    await tester.pumpWidget(_app(exists: true, backend: _FakeBackend()));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump(); // resolve unlock future
      await tester.pump(const Duration(milliseconds: 500)); // settle shake
    }

    expect(find.textContaining('请等待'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    // 排空递增等待的 periodic timer（2 秒），避免 teardown 报 pending timer。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('create mode renders for a missing vault', (tester) async {
    await tester.pumpWidget(_app(exists: false));
    await tester.pumpAndSettle();

    expect(find.text('创建新保险库'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建保险库'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('create blocks a weak password', (tester) async {
    await tester.pumpWidget(_app(exists: false, backend: _FakeBackend()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.enterText(find.byType(TextField).last, 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '创建保险库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('主密码强度不足，请使用更复杂的密码'), findsOneWidget);
    expect(find.text('MAIN-PLACEHOLDER'), findsNothing);
  });

  testWidgets('create with matching strong password navigates to main', (
    tester,
  ) async {
    await tester.pumpWidget(_app(exists: false, backend: _FakeBackend()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, _strong);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, _strong);
    await tester.tap(find.widgetWithText(FilledButton, '创建保险库'));
    await tester.pumpAndSettle();

    expect(find.text('MAIN-PLACEHOLDER'), findsOneWidget);
  });
}
