import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell/main_page.dart';

/// 解锁页占位（T2.6 按 7.2 原型实现：库选择器 + 主密码 + 递增等待）。
class UnlockPage extends StatelessWidget {
  const UnlockPage({super.key});

  static const path = '/unlock';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 12),
            Text('PwVault', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('保险库已锁定'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go(MainPage.path),
              child: const Text('解锁（占位）'),
            ),
          ],
        ),
      ),
    );
  }
}
