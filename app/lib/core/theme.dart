import 'package:flutter/material.dart';

/// 亮/暗主题（T0.1 占位，视觉规格随第 7 章原型在 M2 细化）。
abstract final class AppTheme {
  static const _seed = Color(0xFF185FA5);

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    useMaterial3: true,
  );

  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
