//! FFI API 暴露层（T0.2：连通性验证；契约见 PDR 12.7，后续只增不改）。

use flutter_rust_bridge::frb;

/// 连通性探针：返回 crate 名与版本，供三端验证 FFI 链路。
#[frb(sync)]
pub fn ping() -> String {
    format!("core_crypto {}", env!("CARGO_PKG_VERSION"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ping_returns_crate_version() {
        assert_eq!(ping(), format!("core_crypto {}", env!("CARGO_PKG_VERSION")));
    }
}
