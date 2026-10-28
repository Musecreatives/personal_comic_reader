import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:shaddai_reader/core/sources/hidden_sources_store.dart';

void main() {
  setUp(() async => await setUpTestHive());
  tearDown(() async => await tearDownTestHive());

  test('hiding and showing a source', () async {
    final store = HiddenSourcesStore();
    await store.init();
    expect(store.isHidden('42'), isFalse);

    await store.setHidden('42', true);
    expect(store.isHidden('42'), isTrue);

    await store.setHidden('42', false);
    expect(store.isHidden('42'), isFalse);
  });

  test('visible() drops hidden sources and keeps the order', () async {
    final store = HiddenSourcesStore();
    await store.init();
    await store.setHidden('b', true);

    const all = [
      (id: 'a', name: 'A', lang: 'en'),
      (id: 'b', name: 'B', lang: 'en'),
      (id: 'c', name: 'C', lang: 'en'),
    ];
    expect(store.visible(all).map((s) => s.id), ['a', 'c']);
  });

  test('the sync bookkeeping key never counts as a hidden source', () async {
    final store = HiddenSourcesStore();
    await store.init();
    await store.setHidden('42', true);
    expect(store.hiddenIds, {'42'});
  });
}
