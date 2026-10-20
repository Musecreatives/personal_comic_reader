import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shaddai_reader/backends/opds/opds_backend.dart';
import 'package:shaddai_reader/core/backend/reader_backend.dart';

const _rootFeed = '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>root</id>
  <title>Test OPDS catalog</title>
  <entry>
    <title>All series</title>
    <id>allSeries</id>
    <link type="application/atom+xml;profile=opds-catalog;kind=navigation"
          rel="subsection" href="http://test.local/opds/series" />
  </entry>
</feed>
''';

const _seriesFeed = '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>series1</id>
  <title>Absolute Batman</title>
  <subtitle>A dark knight story.</subtitle>
  <entry>
    <title>Book 1</title>
    <id>book1</id>
    <link rel="http://opds-spec.org/image/thumbnail"
          href="http://test.local/opds/book1/thumbnail" />
    <link rel="http://vaemendis.net/opds-pse/stream"
          xmlns:pse="http://vaemendis.net/opds-pse/ns"
          pse:count="24"
          pse:lastRead="0"
          href="http://test.local/opds/book1/page/{pageNumber}" />
  </entry>
  <entry>
    <title>Book 2 (CBZ only)</title>
    <id>book2</id>
    <link rel="http://opds-spec.org/acquisition"
          type="application/zip"
          href="http://test.local/opds/book2.cbz" />
  </entry>
</feed>
''';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late OpdsBackend backend;

  const config = ServerConfig(
    id: 's1',
    name: 'Test OPDS',
    type: ServerType.opds,
    baseUrl: 'http://test.local/opds/catalog',
    username: 'user',
  );

  setUp(() {
    dio = Dio();
    adapter = DioAdapter(dio: dio);
    dio.httpClientAdapter = adapter;
    backend = OpdsBackend(config: config, password: 'pw', dio: dio);
  });

  test('listLibraries() maps navigation entries in the root catalog',
      () async {
    adapter.onGet(
      'http://test.local/opds/catalog',
      (server) => server.reply(200, _rootFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );

    final libraries = await backend.listLibraries();

    expect(libraries.single.name, 'All series');
    expect(libraries.single.id, 'http://test.local/opds/series');
  });

  test('listSeries() maps subsection entries under a library feed',
      () async {
    adapter.onGet(
      'http://test.local/opds/series',
      (server) => server.reply(200, _rootFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );

    final result =
        await backend.listSeries(libraryId: 'http://test.local/opds/series');

    expect(result.items.single.title, 'All series');
  });

  test('listBooks() reads pse:count for the PSE-streamed book and 0 for '
      'the CBZ-only one until it is unzipped', () async {
    adapter.onGet(
      'http://test.local/opds/series1',
      (server) => server.reply(200, _seriesFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );

    final books = await backend.listBooks('http://test.local/opds/series1');

    expect(books, hasLength(2));
    expect(books[0].title, 'Book 1');
    expect(books[0].pageCount, 24);
    expect(books[1].title, 'Book 2 (CBZ only)');
    expect(books[1].pageCount, 0);
  });

  test('fetchPage() substitutes {pageNumber} in the PSE stream URL',
      () async {
    adapter.onGet(
      'http://test.local/opds/series1',
      (server) => server.reply(200, _seriesFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );
    await backend.listBooks('http://test.local/opds/series1');

    adapter.onGet(
      'http://test.local/opds/book1/page/5',
      (server) => server.reply(200, Uint8List.fromList([1, 2, 3])),
    );

    final bytes = await backend.fetchPage('book1', 5);

    expect(bytes, [1, 2, 3]);
  });

  test('fetchPage() falls back to downloading and unzipping the CBZ, '
      'sorted by filename, when there is no PSE stream', () async {
    adapter.onGet(
      'http://test.local/opds/series1',
      (server) => server.reply(200, _seriesFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );
    await backend.listBooks('http://test.local/opds/series1');

    final archive = Archive()
      ..addFile(ArchiveFile('page_001.jpg', 11, utf8.encode('second page')))
      ..addFile(ArchiveFile('page_000.jpg', 10, utf8.encode('first page')))
      ..addFile(ArchiveFile('ComicInfo.xml', 13, utf8.encode('<ComicInfo/>')));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    adapter.onGet(
      'http://test.local/opds/book2.cbz',
      (server) => server.reply(200, zipBytes),
    );

    final page0 = await backend.fetchPage('book2', 0);
    final page1 = await backend.fetchPage('book2', 1);

    expect(utf8.decode(page0), 'first page');
    expect(utf8.decode(page1), 'second page');
  });

  test('getBook() determines page count for a CBZ-only book by unzipping it',
      () async {
    adapter.onGet(
      'http://test.local/opds/series1',
      (server) => server.reply(200, _seriesFeed,
          headers: {'content-type': ['application/atom+xml']}),
    );
    await backend.listBooks('http://test.local/opds/series1');

    final archive = Archive()
      ..addFile(ArchiveFile('001.jpg', 1, utf8.encode('a')))
      ..addFile(ArchiveFile('002.jpg', 1, utf8.encode('b')))
      ..addFile(ArchiveFile('003.jpg', 1, utf8.encode('c')));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    adapter.onGet(
      'http://test.local/opds/book2.cbz',
      (server) => server.reply(200, zipBytes),
    );

    final book = await backend.getBook('book2');

    expect(book.pageCount, 3);
  });

  test('getBook()/fetchPage() throw a clear error for an unseen book id',
      () async {
    expect(() => backend.getBook('never-listed'), throwsStateError);
    expect(() => backend.fetchPage('never-listed', 0), throwsStateError);
  });
}
