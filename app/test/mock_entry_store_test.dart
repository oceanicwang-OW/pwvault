import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pwvault/features/list/mock_entry_store.dart';
import 'package:pwvault/services/vault_service.dart';

EntryDraft _draft({
  String? id,
  String title = '新条目',
  List<String> tags = const [],
  String? totpUri,
}) => EntryDraft(
  id: id,
  title: title,
  username: '',
  password: '',
  url: '',
  notes: '',
  totpUri: totpUri,
  tags: tags,
  favorite: false,
);

void main() {
  test('seeds six entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mockEntryStoreProvider), hasLength(6));
  });

  test('upsert without id creates and prepends a new entry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(mockEntryStoreProvider.notifier);

    store.upsert(_draft(title: '新主机', totpUri: 'otpauth://x'));

    final entries = container.read(mockEntryStoreProvider);
    expect(entries, hasLength(7));
    expect(entries.first.title, '新主机');
    expect(entries.first.id, startsWith('entry-'));
    expect(entries.first.hasTotp, isTrue);
  });

  test('upsert with an existing id updates in place and keeps createdAt', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(mockEntryStoreProvider.notifier);
    final original = container
        .read(mockEntryStoreProvider)
        .firstWhere((e) => e.id == 'taobao');

    store.upsert(_draft(id: 'taobao', title: '淘宝 Plus'));

    final entries = container.read(mockEntryStoreProvider);
    expect(entries, hasLength(6));
    final updated = entries.firstWhere((e) => e.id == 'taobao');
    expect(updated.title, '淘宝 Plus');
    expect(updated.createdAt, original.createdAt);
  });
}
