import 'package:go_router/go_router.dart';

import '../features/settings/settings_page.dart';
import '../features/shell/main_page.dart';
import '../features/unlock/unlock_page.dart';

/// 路由表：解锁页为入口；自动锁定后统一退回 /unlock（T2.3 接管）。
final appRouter = GoRouter(
  initialLocation: UnlockPage.path,
  routes: [
    GoRoute(path: UnlockPage.path, builder: (_, _) => const UnlockPage()),
    GoRoute(path: MainPage.path, builder: (_, _) => const MainPage()),
    GoRoute(path: SettingsPage.path, builder: (_, _) => const SettingsPage()),
  ],
);
