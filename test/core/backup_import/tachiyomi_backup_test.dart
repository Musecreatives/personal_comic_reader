import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/core/backup_import/tachiyomi_backup.dart';

/// A tiny protobuf writer, enough to build Mihon-shaped backups by hand.
class _Pb {
  final _b = BytesBuilder();

  void _varint(BigInt v) {
    var x = v.isNegative ? v + (BigInt.one << 64) : v;
    do {
      var byte = (x & BigInt.from(0x7f)).toInt();
      x >>= 7;
      if (x > BigInt.zero) byte |= 0x80;
      _b.addByte(byte);
    } while (x > BigInt.zero);
  }

  _Pb int64(int field, String value) {
    _varint(BigInt.from(field << 3));
    _varint(BigInt.parse(value));
    return this;
  }

  _Pb bytes(int field, List<int> value) {
    _varint(BigInt.from(field << 3 | 2));
    _varint(BigInt.from(value.length));
    _b.add(value);
    return this;
  }

  _Pb text(int field, String value) => bytes(field, utf8.encode(value));
  _Pb msg(int field, _Pb m) => bytes(field, m.done());

  _Pb float(int field, double value) {
    _varint(BigInt.from(field << 3 | 5));
    _b.add((ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List());
    return this;
  }

  Uint8List done() => _b.toBytes();
}

_Pb _chapter(double number, {required bool read}) =>
    _Pb().text(2, 'Ch $number').int64(4, read ? '1' : '0').float(9, number);

void main() {
  test('reads titles, exact source ids, categories and read chapters', () {
    final backup = _Pb()
        .msg(1, _Pb()
            .int64(1, '-1234567890123456789') // a negative 64-bit id
            .text(2, '/series/mount-hua')
            .text(3, 'Return of the Mount Hua Sect')
            .msg(16, _chapter(1, read: true))
            .msg(16, _chapter(2, read: true))
            .msg(16, _chapter(2.5, read: false))
            .int64(17, '3'))
        .msg(1, _Pb()
            .int64(1, '6247824327199706550')
            .text(2, '/gone')
            .text(3, 'Taken out of the library')
            .int64(100, '0'))
        .msg(2, _Pb().text(1, 'Murim').int64(2, '3'))
        .msg(101, _Pb().text(1, 'Asura Scans').int64(2, '-1234567890123456789'));
    final gz = Uint8List.fromList(const GZipEncoder().encode(backup.done()));

    expect(isTachiyomiBackup(gz), isTrue);
    final parsed = TachiyomiBackupParser.parse(gz);
    expect(parsed.titles, hasLength(1));
    final t = parsed.titles.single;
    expect(t.primaryTitle, 'Return of the Mount Hua Sect');
    expect(t.tabs, ['Murim']);
    final s = t.sources.single;
    expect(s.suwayomiSourceId, '-1234567890123456789');
    expect(s.sourceId, 'Asura Scans');
    expect(s.url, '/series/mount-hua');
    expect((s.chapterCount, s.readCount), (3, 2));
    final progress = parsed.progressBySourceManga[s.sourceUuid]!;
    expect(progress.map((p) => (p.chapNum, p.completed)), [(1.0, true), (2.0, true), (2.5, false)]);
  });

  test('a Paperback backup (zip) is not taken for a Tachiyomi one', () {
    expect(isTachiyomiBackup(Uint8List.fromList([0x50, 0x4b, 3, 4])), isFalse);
  });

  test('finds the extension package for a source id in a repo index', () {
    final index = _Pb().msg(1, _Pb()
        .msg(1, _Pb()
            .text(1, 'MangaGeko')
            .text(2, 'eu.kanade.tachiyomi.extension.en.mangarawclub')
            .msg(9, _Pb().text(1, 'MangaGeko').text(2, 'en').int64(3, '734865402529567092')))
        .msg(1, _Pb()
            .text(1, 'Asura Scans')
            .text(2, 'eu.kanade.tachiyomi.extension.en.asurascans')
            .msg(9, _Pb().text(1, 'Asura Scans').int64(3, '6247824327199706550'))));
    final gz = Uint8List.fromList(const GZipEncoder().encode(index.done()));
    expect(extensionsForSources(gz, {'734865402529567092', '42'}),
        {'734865402529567092': 'eu.kanade.tachiyomi.extension.en.mangarawclub'});
  });

  test('repo index addresses work from a browser', () {
    expect(repoIndexUrl('https://github.com/keiyoushi/extensions/raw/repo/index.pb'),
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb');
    expect(repoIndexUrl('https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json'),
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb');
  });

  // Real files stay out of the repo (a friend's backup is theirs). Point
  // TACHIBK / REPO_INDEX at local copies to check against them.
  final real = Platform.environment['TACHIBK'];
  test('a real backup parses', () {
    final parsed = TachiyomiBackupParser.parse(File(real!).readAsBytesSync());
    expect(parsed.titles, isNotEmpty);
    final bySource = <String, int>{};
    for (final t in parsed.titles) {
      bySource.update(t.sources.single.sourceId, (n) => n + 1, ifAbsent: () => 1);
    }
    // ignore: avoid_print
    print('titles ${parsed.titles.length}: $bySource');
    final ids = {for (final t in parsed.titles) t.sources.single.suwayomiSourceId!};
    final index = Platform.environment['REPO_INDEX'];
    if (index != null) {
      // ignore: avoid_print
      print('packages: ${extensionsForSources(File(index).readAsBytesSync(), ids)}');
    }
  }, skip: real == null ? 'set TACHIBK to a .tachibk to run' : false);
}
