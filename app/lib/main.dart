import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge/frb_generated.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'services/autolock_service.dart';
import 'services/clipboard_service.dart';
import 'services/local_config.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: PwVaultApp()));
}

class PwVaultApp extends ConsumerStatefulWidget {
  const PwVaultApp({super.key});

  @override
  ConsumerState<PwVaultApp> createState() => _PwVaultAppState();
}

class _PwVaultAppState extends ConsumerState<PwVaultApp> {
  var _hydrated = false;

  /// 把落盘的偏好水合到运行时 provider（仅在配置首次就绪时执行一次）。
  void _hydrate(AppConfig config) {
    final mode = switch (config.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
    if (mode != null) ref.read(themeModeProvider.notifier).set(mode);

    final autoLock = config.autoLockSeconds;
    if (autoLock != null && autoLock > 0) {
      ref.read(autoLockTimeoutProvider.notifier).setTimeout(
        Duration(seconds: autoLock),
      );
    }
    final clipboard = config.clipboardSeconds;
    if (clipboard != null && clipboard > 0) {
      ref.read(clipboardClearAfterProvider.notifier).setClearAfter(
        Duration(seconds: clipboard),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppConfig>>(appConfigProvider, (_, next) {
      final data = next.asData;
      if (!_hydrated && data != null) {
        _hydrated = true;
        _hydrate(data.value);
      }
    });
    ref.watch(appConfigProvider); // 触发配置加载

    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'PwVault',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
