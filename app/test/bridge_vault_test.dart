import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/bridge/api.dart';
import 'package:pwvault/bridge/frb_generated.dart';

String _libPath() => Platform.isWindows
    ? '../core_crypto/target/debug/core_crypto.dll'
    : Platform.isMacOS
        ? '../core_crypto/target/debug/libcore_crypto.dylib'
        : '../core_crypto/target/debug/libcore_crypto.so';

void main() {
  setUpAll(() async {
    final lib = _libPath();
    expect(
      File(lib).existsSync(),
      isTrue,
      reason: '动态库缺失：先在 core_crypto/ 下 cargo build 再跑本测试',
    );
    await RustLib.init(externalLibrary: ExternalLibrary.open(lib));
  });

  test('VaultHandle 全链路：建库→增删改查→改密→锁定', () async {
    final dir = Directory.systemTemp.createTempSync('pwvault_t18');
    final path = '${dir.path}/vault.pwvault';

    try {
      // 建库
      final h = await VaultHandle.create(path: path, password: 'master');
      expect(await h.listMeta(), isEmpty);

      // 增
      final meta = await h.upsert(
        draft: const EntryDraft(
          title: '淘宝',
          username: 'owen@163.com',
          password: 'kQ9#mTr2!vLp',
          url: 'taobao.com',
          notes: 'note marker',
          totpUri: 'otpauth://totp/x?secret=ABC',
          tags: ['个人', '购物'],
          favorite: true,
        ),
      );
      expect(meta.title, '淘宝');
      expect(meta.hasTotp, isTrue);
      expect(meta.favorite, isTrue);

      // 查（列表 / 单条解密 / 完整明文）
      final metas = await h.listMeta();
      expect(metas.length, 1);
      expect(metas.first.id, meta.id);
      expect(await h.revealPassword(id: meta.id), 'kQ9#mTr2!vLp');
      final full = await h.getFull(id: meta.id);
      expect(full.password, 'kQ9#mTr2!vLp');
      expect(full.totpUri, 'otpauth://totp/x?secret=ABC');
      expect(full.tags, ['个人', '购物']);

      // 改
      final meta2 = await h.upsert(
        draft: EntryDraft(
          id: meta.id,
          title: '淘宝-改',
          username: full.username,
          password: full.password,
          url: full.url,
          notes: full.notes,
          totpUri: full.totpUri,
          tags: full.tags,
          favorite: false,
        ),
      );
      expect(meta2.id, meta.id);
      expect(meta2.title, '淘宝-改');
      expect(meta2.favorite, isFalse);

      // 删 → 回收站 → 恢复
      await h.softDelete(id: meta.id);
      expect(await h.listMeta(), isEmpty);
      final trash = await h.listTrash();
      expect(trash.length, 1);
      expect(trash.first.deletedAt, isNotNull);
      await h.restore(id: meta.id);
      expect((await h.listMeta()).length, 1);

      // 错误密码解锁失败（带 WRONG_PASSWORD 码）
      await expectLater(
        VaultHandle.unlock(path: path, password: 'wrong'),
        throwsA(predicate((e) => e.toString().contains('WRONG_PASSWORD'))),
      );

      // 改密 → 旧密码失效、新密码可用且数据完整（锁定=释放句柄）
      await h.changePassword(old: 'master', new_: 'master2');
      await expectLater(
        VaultHandle.unlock(path: path, password: 'master'),
        throwsA(anything),
      );
      final h2 = await VaultHandle.unlock(path: path, password: 'master2');
      final after = await h2.listMeta();
      expect(after.length, 1);
      expect(after.first.title, '淘宝-改');
      expect(await h2.revealPassword(id: meta.id), 'kQ9#mTr2!vLp');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
