import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/unlock/unlock_page.dart';
import 'package:pwvault/features/unlock/vault_location.dart';
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
  group('AppConfigNotifier.recordVault', () {
    test('dedups, moves to front, and persists', () async {
      final store = _MemStore();
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(appConfigProvider.future);
      final notifier = container.read(appConfigProvider.notifier);
      await notifier.recordVault('/v/a.pwvault');
      await notifier.recordVault('/v/b.pwvault');
      await notifier.recordVault('/v/a.pwvault');

      expect(container.read(appConfigProvider).asData?.value.recentVaults, [
        '/v/a.pwvault',
        '/v/b.pwvault',
      ]);
      expect(store.saved.recentVaults, ['/v/a.pwvault', '/v/b.pwvault']);
    });

    test('caps the recent list at 8', () async {
      final store = _MemStore();
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(appConfigProvider.future);
      final notifier = container.read(appConfigProvider.notifier);
      for (var i = 0; i < 12; i++) {
        await notifier.recordVault('/v/$i.pwvault');
      }

      final recents = container.read(appConfigProvider).asData!.value.recentVaults;
      expect(recents, hasLength(8));
      expect(recents.first, '/v/11.pwvault');
    });
  });

  testWidgets('selecting a recent vault updates selectedVaultPathProvider', (
    tester,
  ) async {
    final store = _MemStore(
      const AppConfig(recentVaults: ['/x/work.pwvault', '/y/home.pwvault']),
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
        child: const MaterialApp(home: UnlockPage()),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockPage)),
    );
    expect(container.read(selectedVaultPathProvider), isNull);

    await tester.tap(find.byTooltip('选择保险库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('work.pwvault').last);
    await tester.pumpAndSettle();

    expect(container.read(selectedVaultPathProvider), '/x/work.pwvault');
  });
}
