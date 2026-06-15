import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 库文件位置及其是否已建立。
class VaultLocation {
  final String path;
  final bool exists;

  const VaultLocation({required this.path, required this.exists});
}

/// 默认库文件位置：应用文档目录下 `pwvault/vault.pwvault`（首次使用的库）。
final defaultVaultPathProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final vaultDir = Directory('${dir.path}/pwvault');
  await vaultDir.create(recursive: true);
  return '${vaultDir.path}/vault.pwvault';
});

/// 当前在解锁页选中的库路径；null 表示使用默认库。
final selectedVaultPathProvider =
    NotifierProvider<SelectedVaultPathNotifier, String?>(
      SelectedVaultPathNotifier.new,
    );

class SelectedVaultPathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String path) => state = path;
}

/// 解析出的当前库位置：选中库优先，否则默认库；`exists` 决定解锁/建库模式。
final vaultLocationProvider = FutureProvider<VaultLocation>((ref) async {
  final selected = ref.watch(selectedVaultPathProvider);
  final String path = selected ??
      await ref.watch(defaultVaultPathProvider.future);
  return VaultLocation(path: path, exists: File(path).existsSync());
});
