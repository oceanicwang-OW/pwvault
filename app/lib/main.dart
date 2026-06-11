import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge/frb_generated.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: PwVaultApp()));
}

class PwVaultApp extends ConsumerWidget {
  const PwVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
