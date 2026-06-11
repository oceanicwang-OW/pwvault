import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../unlock/unlock_page.dart';

/// 主界面占位（T2.7 实现三栏 Shell：侧边栏 140 / 列表 220 / 详情自适应）。
class MainPage extends StatelessWidget {
  const MainPage({super.key});

  static const path = '/main';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PwVault — 主界面（占位）'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '锁定',
            onPressed: () => context.go(UnlockPage.path),
          ),
        ],
      ),
      body: const Center(child: Text('列表 / 详情三栏布局由 T2.7 实现')),
    );
  }
}
