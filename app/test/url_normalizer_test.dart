import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/edit/url_normalizer.dart';

void main() {
  test('empty / whitespace stays empty', () {
    expect(normalizeUrl(''), '');
    expect(normalizeUrl('   '), '');
  });

  test('adds https:// when scheme is missing', () {
    expect(normalizeUrl('example.com'), 'https://example.com');
  });

  test('lowercases scheme and host but keeps path case', () {
    expect(normalizeUrl('EXAMPLE.com/Path'), 'https://example.com/Path');
    expect(normalizeUrl('HTTP://Example.com'), 'http://example.com');
  });

  test('strips a bare trailing slash', () {
    expect(normalizeUrl('https://example.com/'), 'https://example.com');
  });
}
