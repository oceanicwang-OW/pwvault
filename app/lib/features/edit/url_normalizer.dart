/// 规范化用户输入的网址（T2.10）：
/// - 去首尾空白；空串原样返回；
/// - 缺少 scheme 时补 `https://`；
/// - scheme 与 host 转小写，path/query 等保持原样；
/// - 去掉末尾多余的 `/`（但保留根路径单个站点不加）。
///
/// 解析失败（非法 URL）时退回去空白后的原值，避免吞掉用户输入。
String normalizeUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
  final candidate = hasScheme ? trimmed : 'https://$trimmed';

  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return trimmed;

  final normalized = uri.replace(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
  );

  var result = normalized.toString();
  if (result.endsWith('/') && normalized.path == '/') {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
