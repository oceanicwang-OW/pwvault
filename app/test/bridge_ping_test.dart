import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/bridge/api.dart';
import 'package:pwvault/bridge/frb_generated.dart';

void main() {
  test('FFI ping 返回 core_crypto 版本串', () async {
    final lib = Platform.isWindows
        ? '../core_crypto/target/debug/core_crypto.dll'
        : Platform.isMacOS
            ? '../core_crypto/target/debug/libcore_crypto.dylib'
            : '../core_crypto/target/debug/libcore_crypto.so';
    expect(
      File(lib).existsSync(),
      isTrue,
      reason: '动态库缺失：先在 core_crypto/ 下运行 cargo build 再执行本测试',
    );
    await RustLib.init(externalLibrary: ExternalLibrary.open(lib));
    expect(ping(), matches(RegExp(r'^core_crypto \d+\.\d+\.\d+$')));
  });
}
