import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 库外本地配置（PDR §5.4：最近库列表等，明文、不参与同步，不含任何敏感字段）。
class AppConfig {
  final List<String> recentVaults;

  const AppConfig({this.recentVaults = const []});

  AppConfig copyWith({List<String>? recentVaults}) =>
      AppConfig(recentVaults: recentVaults ?? this.recentVaults);

  Map<String, dynamic> toJson() => {'recentVaults': recentVaults};

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    recentVaults:
        (json['recentVaults'] as List?)?.whereType<String>().toList() ??
        const [],
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

  /// 记录最近打开的库：去重、置顶、限长，并持久化（失败不阻断）。
  Future<void> recordVault(String path) async {
    final current = state.asData?.value ?? const AppConfig();
    final recents = [
      path,
      ...current.recentVaults.where((p) => p != path),
    ].take(_maxRecentVaults).toList();
    final config = current.copyWith(recentVaults: recents);
    state = AsyncData(config);
    try {
      await _store.save(config);
    } catch (_) {
      // 内存态已更新；持久化失败静默忽略。
    }
  }
}
