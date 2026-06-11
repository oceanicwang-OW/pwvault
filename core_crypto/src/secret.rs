//! 机密内存类型（T1.1）：持有期间可显式访问，drop 时自动清零。
//!
//! 分层禁令（PDR 3.3 / 12.0）：这些类型的内部字节永不跨 FFI 边界交给 Dart；
//! Dart 只允许持有 `VaultHandle` 句柄与单条明文密码的瞬时引用。

use std::fmt;

use zeroize::{Zeroize, ZeroizeOnDrop};

/// 机密字节串（KEK / DEK 等），drop 时自动清零。
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SecretBytes(Vec<u8>);

impl SecretBytes {
    pub fn new(bytes: Vec<u8>) -> Self {
        Self(bytes)
    }

    /// 显式访问内部字节；调用方不得复制出超出当前作用域的副本。
    pub fn expose(&self) -> &[u8] {
        &self.0
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl fmt::Debug for SecretBytes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SecretBytes(<{} bytes redacted>)", self.0.len())
    }
}

/// 机密字符串（主密码等），drop 时自动清零。
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SecretString(String);

impl SecretString {
    pub fn new(s: String) -> Self {
        Self(s)
    }

    /// 显式访问内部字符串；调用方不得复制出超出当前作用域的副本。
    pub fn expose(&self) -> &str {
        &self.0
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl From<String> for SecretString {
    fn from(s: String) -> Self {
        Self::new(s)
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SecretString(<redacted>)")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_output_is_redacted() {
        let b = SecretBytes::new(vec![0xAA; 4]);
        let s = SecretString::new("hunter2".into());
        assert_eq!(format!("{b:?}"), "SecretBytes(<4 bytes redacted>)");
        assert!(!format!("{s:?}").contains("hunter2"));
    }

    #[test]
    fn explicit_zeroize_clears_bytes() {
        let mut b = SecretBytes::new(vec![0xAA; 32]);
        b.zeroize();
        assert!(b.is_empty());

        let mut s = SecretString::new("master-password".into());
        s.zeroize();
        assert!(s.is_empty());
    }

    /// drop 后原缓冲区被清零。
    ///
    /// 注意：drop 后读原指针是测试专用手法（与 zeroize crate 自身测试一致），
    /// 依赖分配器未立即复用该内存；仅用于验收，不代表安全的生产模式。
    #[test]
    fn drop_zeroizes_underlying_buffer() {
        let v = vec![0xABu8; 32];
        let ptr = v.as_ptr();
        let b = SecretBytes::new(v);
        assert_eq!(unsafe { *ptr }, 0xAB);
        drop(b);
        let leaked = (0..32).any(|i| unsafe { *ptr.add(i) } == 0xAB);
        assert!(!leaked, "drop 后缓冲区仍残留明文字节");
    }
}
