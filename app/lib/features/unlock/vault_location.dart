import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 库文件位置及其是否已建立。
class VaultLocation {
  final String path;
  final bool exists;

  const VaultLocation({required this.path, required this.exists});
}

/// 默认库文件位置：应用文档目录下 `pwvault/vault.pwvault`。
///
/// 核心解锁流程（T2.6）固定单库；多库选择器与最近库列表持久化留待后续任务。
/// `exists` 决定解锁页进入「解锁」还是「建库」模式。
final vaultLocationProvider = FutureProvider<VaultLocation>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final vaultDir = Directory('${dir.path}/pwvault');
  await vaultDir.create(recursive: true);
  final path = '${vaultDir.path}/vault.pwvault';
  return VaultLocation(path: path, exists: File(path).existsSync());
});
