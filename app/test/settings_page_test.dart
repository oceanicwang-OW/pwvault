import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pwvault/features/settings/settings_page.dart';
import 'package:pwvault/features/unlock/unlock_page.dart';
import 'package:pwvault/services/autolock_service.dart';
import 'package:pwvault/services/clipboard_service.dart';
import 'package:pwvault/services/vault_service.dart';
import 'package:pwvault/core/providers.dart';

const _correctOld = 'correct-old-master';
const _strongNew = r'x7Km!q9Lp#vRt2Wz';

/// 最小已解锁会话：仅校验改密的当前密码，其余 CRUD 未在设置页用到。
class _FakeSession implements VaultSession {
  bool changed = false;

  @override
  Future<List<EntryMeta>> listMeta() async => const [];

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (oldPassword != _correctOld) {
      throw const WrongPasswordException('WRONG_PASSWORD');
    }
    changed = true;
  }

  @override
  void dispose() {}

  @override
  Object noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeBackend implements VaultBackend {
  final _FakeSession session = _FakeSession();

  @override
  Future<VaultSession> create(String path, String password) async => session;

  @override
  Future<VaultSession> unlock(String path, String password) async => session;
}

GoRouter _router() => GoRouter(
  initialLocation: SettingsPage.path,
  routes: [
    GoRoute(path: SettingsPage.path, builder: (_, _) => const SettingsPage()),
    GoRoute(path: UnlockPage.path, builder: (_, _) => const UnlockPage()),
  ],
);

Widget _routerApp() => MaterialApp.router(routerConfig: _router());

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

void main() {
  testWidgets('theme segment switches themeModeProvider', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _routerApp()));
    final container = _containerOf(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.text('深色'));
    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('auto-lock dropdown updates timeout provider', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _routerApp()));
    final container = _containerOf(tester);
    expect(container.read(autoLockTimeoutProvider), const Duration(minutes: 5));

    await tester.tap(find.text('5 分钟').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 分钟').last);
    await tester.pumpAndSettle();

    expect(
      container.read(autoLockTimeoutProvider),
      const Duration(minutes: 15),
    );
  });

  testWidgets('clipboard dropdown updates clear-after provider', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(child: _routerApp()));
    final container = _containerOf(tester);
    expect(
      container.read(clipboardClearAfterProvider),
      const Duration(seconds: 30),
    );

    await tester.tap(find.text('30 秒').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 秒').last);
    await tester.pumpAndSettle();

    expect(
      container.read(clipboardClearAfterProvider),
      const Duration(seconds: 60),
    );
  });

  testWidgets('weak new password is blocked with an error', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _routerApp()));

    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      _correctOld,
    );
    await tester.enterText(find.widgetWithText(TextField, '新主密码'), 'abc');
    await tester.enterText(find.widgetWithText(TextField, '确认新主密码'), 'abc');
    await tester.ensureVisible(find.text('修改主密码'));
    await tester.tap(find.text('修改主密码'));
    await tester.pump();

    expect(find.text('新主密码强度不足，请使用更复杂的密码'), findsOneWidget);
  });

  testWidgets('mismatched confirmation is blocked', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _routerApp()));

    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      _correctOld,
    );
    await tester.enterText(find.widgetWithText(TextField, '新主密码'), _strongNew);
    await tester.enterText(
      find.widgetWithText(TextField, '确认新主密码'),
      '${_strongNew}X',
    );
    await tester.ensureVisible(find.text('修改主密码'));
    await tester.tap(find.text('修改主密码'));
    await tester.pump();

    expect(find.text('两次输入的新主密码不一致'), findsOneWidget);
  });

  testWidgets('wrong current password surfaces backend error', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      ProviderScope(overrides: [vaultBackendProvider.overrideWithValue(backend)], child: _routerApp()),
    );
    await _containerOf(tester).read(vaultProvider.notifier).unlock('p', 'x');
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      'wrong-old',
    );
    await tester.enterText(find.widgetWithText(TextField, '新主密码'), _strongNew);
    await tester.enterText(
      find.widgetWithText(TextField, '确认新主密码'),
      _strongNew,
    );
    await tester.ensureVisible(find.text('修改主密码'));
    await tester.tap(find.text('修改主密码'));
    await tester.pumpAndSettle();

    expect(find.text('当前主密码不正确'), findsOneWidget);
    expect(backend.session.changed, isFalse);
  });

  testWidgets('successful change locks vault and returns to unlock', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      ProviderScope(overrides: [vaultBackendProvider.overrideWithValue(backend)], child: _routerApp()),
    );
    final container = _containerOf(tester);
    await container.read(vaultProvider.notifier).unlock('p', 'x');
    await tester.pump();
    expect(container.read(vaultStateProvider), VaultStatus.unlocked);

    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      _correctOld,
    );
    await tester.enterText(find.widgetWithText(TextField, '新主密码'), _strongNew);
    await tester.enterText(
      find.widgetWithText(TextField, '确认新主密码'),
      _strongNew,
    );
    await tester.ensureVisible(find.text('修改主密码'));
    await tester.tap(find.text('修改主密码'));
    await tester.pumpAndSettle();

    expect(backend.session.changed, isTrue);
    expect(container.read(vaultStateProvider), VaultStatus.locked);
    expect(find.byType(UnlockPage), findsOneWidget);
  });
}
