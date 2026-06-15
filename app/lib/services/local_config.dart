import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 库外本地配置（PDR §5.4：最近库列表、界面偏好等，明文、不参与同步，
/// 不含任何敏感字段）。`themeMode` 取值 system/light/dark；时长为秒，null 表默认。
class AppConfig {
  final List<String> recentVaults;
  final String? themeMode;
  final int? autoLockSeconds;
  final int? clipboardSeconds;

  const AppConfig({
    this.recentVaults = const [],
    this.themeMode,
    this.autoLockSeconds,
    this.clipboardSeconds,
  });

  AppConfig copyWith({
    List<String>? recentVaults,
    String? themeMode,
    int? autoLockSeconds,
    int? clipboardSeconds,
  }) => AppConfig(
    recentVaults: recentVaults ?? this.recentVaults,
    themeMode: themeMode ?? this.themeMode,
    autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    clipboardSeconds: clipboardSeconds ?? this.clipboardSeconds,
  );

  Map<String, dynamic> toJson() => {
    'recentVaults': recentVaults,
    if (themeMode != null) 'themeMode': themeMode,
    if (autoLockSeconds != null) 'autoLockSeconds': autoLockSeconds,
    if (clipboardSeconds != null) 'clipboardSeconds': clipboardSeconds,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    recentVaults:
        (json['recentVaults'] as List?)?.whereType<String>().toList() ??
        const [],
    themeMode: json['themeMode'] as String?,
    autoLockSeconds: (json['autoLockSeconds'] as num?)?.toInt(),
    clipboardSeconds: (json['clipboardSeconds'] as num?)?.toInt(),
  );
}

abstract interface class ConfigStore {
  Future<AppConfig> load();
  Future<void> save(AppConfig config);
}

/// 配置落盘到应用支持目录 `pwvault/config.json`。
class FileConfigStore implements ConfigStore {
  const FileConfigStore();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final configDir = Directory('${dir.path}/pwvault');
    await configDir.create(recursive: true);
    return File('${configDir.path}/config.json');
  }

  @override
  Future<AppConfig> load() async {
    final file = await _file();
    if (!file.existsSync()) return const AppConfig();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppConfig.fromJson(json);
  }

  @override
  Future<void> save(AppConfig config) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(config.toJson()));
  }
}

final configStoreProvider = Provider<ConfigStore>(
  (ref) => const FileConfigStore(),
);

const _maxRecentVaults = 8;

final appConfigProvider = AsyncNotifierProvider<AppConfigNotifier, AppConfig>(
  AppConfigNotifier.new,
);

class AppConfigNotifier extends AsyncNotifier<AppConfig> {
  ConfigStore get _store => ref.read(configStoreProvider);

  @override
  Future<AppConfig> build() async {
    try {
      return await _store.load();
    } catch (_) {
      // 存储不可用（如纯 widget 测试无平台通道）时降级为空配置。
      return const AppConfig();
    }
  }

  /// 应用变更并持久化：内存态先更新，落盘失败静默忽略（不阻断）。
  Future<void> _mutate(AppConfig Function(AppConfig) transform) async {
    final config = transform(state.asData?.value ?? const AppConfig());
    state = AsyncData(config);
    try {
      await _store.save(config);
    } catch (_) {
      // 内存态已更新；持久化失败静默忽略。
    }
  }

  /// 记录最近打开的库：去重、置顶、限长。
  Future<void> recordVault(String path) => _mutate(
    (c) => c.copyWith(
      recentVaults: [
        path,
        ...c.recentVaults.where((p) => p != path),
      ].take(_maxRecentVaults).toList(),
    ),
  );

  Future<void> setThemeMode(String mode) =>
      _mutate((c) => c.copyWith(themeMode: mode));

  Future<void> setAutoLockSeconds(int seconds) =>
      _mutate((c) => c.copyWith(autoLockSeconds: seconds));

  Future<void> setClipboardSeconds(int seconds) =>
      _mutate((c) => c.copyWith(clipboardSeconds: seconds));
}
