import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/api.dart';

/// 主题模式（T2.12 设置页接管持久化，当前跟随系统）。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

/// core_crypto FFI 连通性探针（T0.2 验收）。
/// bridge 未初始化的环境（如纯 widget 测试）返回占位串。
final coreCryptoVersionProvider = Provider<String>((ref) {
  try {
    return ping();
  } catch (_) {
    return 'bridge offline';
  }
});
