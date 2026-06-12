import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/services/search_index.dart';
import 'package:pwvault/services/vault_service.dart';

EntryMeta _meta(
  String id,
  String title, {
  String username = '',
  String url = '',
  List<String> tags = const [],
  int updatedAt = 0,
}) => EntryMeta(
  id: id,
  title: title,
  username: username,
  url: url,
  tags: tags,
  favorite: false,
  hasTotp: false,
  createdAt: 0,
  updatedAt: updatedAt,
);

void main() {
  group('SearchIndexService', () {
    test('matches Chinese title by Hanzi, full pinyin, and pinyin initials', () {
      final index = SearchIndexService.fromEntries([
        _meta(
          'taobao',
          '淘宝',
          username: 'buyer@example.com',
          url: 'https://taobao.com',
          tags: const ['购物'],
        ),
      ]);

      expect(index.search('淘').map((e) => e.id), ['taobao']);
      expect(index.search('taobao').map((e) => e.id), ['taobao']);
      expect(index.search('tb').map((e) => e.id), ['taobao']);
    });

    test('matches Chinese characters outside the old fixed table', () {
      final index = SearchIndexService.fromEntries([
        _meta('meituan', '美团', tags: const ['外卖']),
        _meta('jd', '京东', tags: const ['购物']),
      ]);

      expect(index.search('meituan').map((e) => e.id), ['meituan']);
      expect(index.search('mt').map((e) => e.id), ['meituan']);
      expect(index.search('jingdong').map((e) => e.id), ['jd']);
      expect(index.search('jd').map((e) => e.id), ['jd']);
    });

    test('uses AND semantics across multiple keywords', () {
      final index = SearchIndexService.fromEntries([
        _meta('a', '淘宝', username: 'alice', tags: const ['personal']),
        _meta('b', '淘宝', username: 'bob', tags: const ['work']),
        _meta('c', 'GitHub', username: 'alice', tags: const ['work']),
      ]);

      expect(index.search('tb alice').map((e) => e.id), ['a']);
      expect(index.search('taobao work').map((e) => e.id), ['b']);
    });

    test('sorts prefix matches before title matches before other matches', () {
      final index = SearchIndexService.fromEntries(
        [
          _meta('tag', 'Work', tags: const ['淘宝'], updatedAt: 30),
          _meta('prefix-old', '淘宝 Admin', updatedAt: 1000),
          _meta('prefix-new', '淘宝 Buyer', updatedAt: 20),
          _meta('title', 'My 淘宝', updatedAt: 40),
        ],
        recentUse: const {
          'prefix-new': 30,
          'prefix-old': 10,
          'title': 40,
          'tag': 50,
        },
      );

      expect(index.search('tb').map((e) => e.id), [
        'prefix-new',
        'prefix-old',
        'title',
        'tag',
      ]);
    });

    test('does not use updatedAt as the tie-breaker for equal matches', () {
      final index = SearchIndexService.fromEntries(
        [
          _meta('edited-old', 'GitHub', updatedAt: 9999),
          _meta('recently-used', 'GitLab', updatedAt: 1),
        ],
        recentUse: const {'recently-used': 200, 'edited-old': 100},
      );

      expect(index.search('git').map((e) => e.id), [
        'recently-used',
        'edited-old',
      ]);
    });

    test('builds and queries 1000 entries inside the PDR budget', () {
      final entries = List<EntryMeta>.generate(
        1000,
        (i) => _meta(
          '$i',
          i == 777 ? '淘宝' : 'Service $i',
          username: 'user$i',
          url: 'https://example$i.com',
          tags: ['tag${i % 10}'],
          updatedAt: i,
        ),
      );

      final buildWatch = Stopwatch()..start();
      final index = SearchIndexService.fromEntries(entries);
      buildWatch.stop();

      final queryWatch = Stopwatch()..start();
      final result = index.search('tb');
      queryWatch.stop();

      expect(result.single.id, '777');
      expect(buildWatch.elapsedMilliseconds, lessThan(200));
      expect(queryWatch.elapsedMilliseconds, lessThan(50));
    });
  });
}
