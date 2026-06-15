import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/core/providers.dart';
import 'package:pwvault/features/settings/settings_page.dart';
import 'package:pwvault/features/unlock/vault_location.dart';
import 'package:pwvault/main.dart';
import 'package:pwvault/services/autolock_service.dart';
import 'package:pwvault/services/local_config.dart';

class _MemStore implements ConfigStore {
  AppConfig saved;
  _MemStore([this.saved = const AppConfig()]);

  @override
  Future<AppConfig> load() async => saved;

  @override
  Future<void> save(AppConfig config) async => saved = config;
}

void main() {
  test('preference setters update state and persist', () async {
    final store = _MemStore();
    final container = ProviderContainer(
      overrides: [configStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(appConfigProvider.future);
    final notifier = container.read(appConfigProvider.notifier);
    await notifier.setThemeMode('dark');
    await notifier.setAutoLockSeconds(900);
    await notifier.setClipboardSeconds(15);

    final config = container.read(appConfigProvider).asData!.value;
    expect(config.themeMode, 'dark');
    expect(config.autoLockSeconds, 900);
    expect(config.clipboardSeconds, 15);
    expect(store.saved.themeMode, 'dark');
    expect(store.saved.autoLockSeconds, 900);
    expect(store.saved.clipboardSeconds, 15);
  });

  testWidgets('startup hydrates saved preferences into runtime providers', (
    tester,
  ) async {
    final store = _MemStore(
      const AppConfig(themeMode: 'dark', autoLockSeconds: 900),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(store),
          vaultLocationProvider.overrideWith(
            (ref) async =>
                const VaultLocation(path: 'dir/vault.pwvault', exists: true),
          ),
        ],
        child: const PwVaultApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PwVaultApp)),
    );
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(
      container.read(autoLockTimeoutProvider),
      const Duration(seconds: 900),
    );
  });

  testWidgets('changing clipboard timeout persists to the store', (
    tester,
  ) async {
    final store = _MemStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [configStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 秒').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 秒').last);
    await tester.pumpAndSettle();

    expect(store.saved.clipboardSeconds, 60);
  });
}
