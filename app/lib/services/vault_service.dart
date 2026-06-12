import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/api.dart';
import '../bridge/store.dart';

export '../bridge/api.dart' show EntryDraft;
export '../bridge/store.dart' show EntryMeta;

// ============================ 领域异常 ============================
//
// bridge 把 Rust 错误抛为 "CODE: message" 串；本层据 CODE 前缀映射为
// 类型化领域异常，UI（T2.6+）按类型处理，不再触碰原始串。

sealed class VaultException implements Exception {
  final String message;
  const VaultException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// 主密码错误（或库头被篡改，密码学上不可区分）。
class WrongPasswordException extends VaultException {
  const WrongPasswordException(super.message);
}

/// 建库时目标路径已存在。
class VaultAlreadyExistsException extends VaultException {
  const VaultAlreadyExistsException(super.message);
}

/// 条目不存在。
class EntryNotFoundException extends VaultException {
  const EntryNotFoundException(super.message);
}

/// 在锁定状态下尝试需要解锁的操作（纯 Dart 侧防护，不来自 Rust）。
class VaultLockedException extends VaultException {
  const VaultLockedException() : super('保险库已锁定');
}

/// 其他未分类错误（IO、损坏、内部错误等）。
class UnknownVaultException extends VaultException {
  const UnknownVaultException(super.message);
}

/// 把 bridge 抛出的对象映射为领域异常。始终抛出，永不返回。
Never mapVaultError(Object error) {
  final msg = error is String ? error : error.toString();
  if (msg.contains('WRONG_PASSWORD')) throw WrongPasswordException(msg);
  if (msg.contains('ALREADY_EXISTS')) throw VaultAlreadyExistsException(msg);
  if (msg.contains('NOT_FOUND')) throw EntryNotFoundException(msg);
  throw UnknownVaultException(msg);
}

// ======================= 后端抽象（可注入） =======================
//
// VaultNotifier 依赖这两个接口而非直接依赖 bridge，单测可注入 fake
// 覆盖解锁失败/锁定清状态等分支，无需加载原生库。

/// 库后端：建库 / 解锁，产出一个已解锁会话。
abstract interface class VaultBackend {
  Future<VaultSession> create(String path, String password);
  Future<VaultSession> unlock(String path, String password);
}

/// 已解锁会话：条目 CRUD + 改密 + 释放（锁定）。
abstract interface class VaultSession {
  Future<List<EntryMeta>> listMeta();
  Future<List<EntryMeta>> listTrash();
  Future<EntryMeta> upsert(EntryDraft draft);
  Future<String> revealPassword(String id);
  Future<EntryDraft> getFull(String id);
  Future<void> softDelete(String id);
  Future<void> restore(String id);
  Future<void> changePassword(String oldPassword, String newPassword);

  /// 释放底层 Rust 句柄（zeroize 密钥）。锁定时调用。
  void dispose();
}

// ===================== 真实 frb 后端实现 =====================

class FrbVaultBackend implements VaultBackend {
  const FrbVaultBackend();

  @override
  Future<VaultSession> create(String path, String password) async {
    try {
      return FrbVaultSession(
        await VaultHandle.create(path: path, password: password),
      );
    } catch (e) {
      mapVaultError(e);
    }
  }

  @override
  Future<VaultSession> unlock(String path, String password) async {
    try {
      return FrbVaultSession(
        await VaultHandle.unlock(path: path, password: password),
      );
    } catch (e) {
      mapVaultError(e);
    }
  }
}

class FrbVaultSession implements VaultSession {
  final VaultHandle _handle;
  FrbVaultSession(this._handle);

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      mapVaultError(e);
    }
  }

  @override
  Future<List<EntryMeta>> listMeta() => _guard(_handle.listMeta);

  @override
  Future<List<EntryMeta>> listTrash() => _guard(_handle.listTrash);

  @override
  Future<EntryMeta> upsert(EntryDraft draft) =>
      _guard(() => _handle.upsert(draft: draft));

  @override
  Future<String> revealPassword(String id) =>
      _guard(() => _handle.revealPassword(id: id));

  @override
  Future<EntryDraft> getFull(String id) =>
      _guard(() => _handle.getFull(id: id));

  @override
  Future<void> softDelete(String id) =>
      _guard(() => _handle.softDelete(id: id));

  @override
  Future<void> restore(String id) => _guard(() => _handle.restore(id: id));

  @override
  Future<void> changePassword(String oldPassword, String newPassword) =>
      _guard(() => _handle.changePassword(old: oldPassword, new_: newPassword));

  @override
  void dispose() => _handle.dispose();
}

// ======================= 状态与 Riverpod =======================

enum VaultStatus { locked, unlocking, unlocked, locking }

/// 库 UI 状态：锁定阶段 + 已解锁条目列表（锁定时为空）。
class VaultData {
  final VaultStatus status;
  final List<EntryMeta> entries;

  const VaultData({required this.status, required this.entries});
  const VaultData.locked() : status = VaultStatus.locked, entries = const [];

  VaultData copyWith({VaultStatus? status, List<EntryMeta>? entries}) =>
      VaultData(
        status: status ?? this.status,
        entries: entries ?? this.entries,
      );
}

/// 后端注入点：应用用真实 frb，单测 override 为 fake。
final vaultBackendProvider = Provider<VaultBackend>(
  (ref) => const FrbVaultBackend(),
);

class VaultNotifier extends Notifier<VaultData> {
  VaultSession? _session;

  VaultBackend get _backend => ref.read(vaultBackendProvider);

  @override
  VaultData build() {
    ref.onDispose(() => _session?.dispose());
    return const VaultData.locked();
  }

  Future<void> create(String path, String password) =>
      _open(() => _backend.create(path, password));

  Future<void> unlock(String path, String password) =>
      _open(() => _backend.unlock(path, password));

  /// 锁定：释放会话（zeroize 密钥）并清空内存状态。
  Future<void> lock() async {
    state = state.copyWith(status: VaultStatus.locking);
    _session?.dispose();
    _session = null;
    state = const VaultData.locked();
  }

  Future<EntryMeta> upsert(EntryDraft draft) async {
    final meta = await _require().upsert(draft);
    await _refresh();
    return meta;
  }

  Future<void> softDelete(String id) async {
    await _require().softDelete(id);
    await _refresh();
  }

  Future<void> restore(String id) async {
    await _require().restore(id);
    await _refresh();
  }

  // 以下转发方法标记 async，使锁定时 _require() 的抛出统一表现为
  // Future 拒绝（而非同步异常），调用方可一致地 await/catch。
  Future<List<EntryMeta>> listTrash() async => _require().listTrash();

  Future<String> revealPassword(String id) async => _require().revealPassword(id);

  Future<EntryDraft> getFull(String id) async => _require().getFull(id);

  Future<void> changePassword(String oldPassword, String newPassword) async =>
      _require().changePassword(oldPassword, newPassword);

  Future<void> _open(Future<VaultSession> Function() opener) async {
    state = const VaultData(status: VaultStatus.unlocking, entries: []);
    try {
      final session = await opener();
      final entries = await session.listMeta();
      _session = session;
      state = VaultData(status: VaultStatus.unlocked, entries: entries);
    } catch (_) {
      _session?.dispose();
      _session = null;
      state = const VaultData.locked();
      rethrow;
    }
  }

  VaultSession _require() {
    final session = _session;
    if (session == null) throw const VaultLockedException();
    return session;
  }

  Future<void> _refresh() async {
    final session = _session;
    if (session == null) return;
    state = state.copyWith(entries: await session.listMeta());
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultData>(
  VaultNotifier.new,
);

/// 仅库锁定阶段（PDR 12.7 vaultStateProvider）。
final vaultStateProvider = Provider<VaultStatus>(
  (ref) => ref.watch(vaultProvider).status,
);

/// 已解锁条目列表（PDR 12.7 entryListProvider）。
final entryListProvider = Provider<List<EntryMeta>>(
  (ref) => ref.watch(vaultProvider).entries,
);
