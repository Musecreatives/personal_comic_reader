/// Tachiyomi / Mihon (and forks: TachiyomiJ2K, Komikku, ...) backups: a
/// gzipped protobuf `.tachibk` (older: `.proto.gz`). Read into the same
/// [PaperbackBackup] model the import screen already shows, with each
/// source carrying its exact Suwayomi source id and the title's address on
/// it - Suwayomi runs the same extensions, so both match one to one.
///
/// Field numbers are Mihon's (eu.kanade.tachiyomi.data.backup.models).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'paperback_backup.dart';

/// One protobuf field. [value] is a varint as an unsigned decimal string
/// (source ids are 64-bit, beyond a web build's exact integers); [bytes]
/// is a length-delimited or fixed-width payload.
class _Field {
  final int number;
  final int wire;
  final String? value;
  final Uint8List? bytes;
  const _Field(this.number, this.wire, {this.value, this.bytes});

  int get asInt => int.tryParse(value ?? '') ?? 0;
  String get asText => bytes == null ? '' : _utf8(bytes!);
}

String _utf8(Uint8List b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    return '';
  }
}

/// Signed 64-bit, as text: Tachiyomi source ids are Java longs.
String _signed(String unsigned) {
  final v = BigInt.parse(unsigned);
  return (v >= BigInt.one << 63 ? v - (BigInt.one << 64) : v).toString();
}

List<_Field> _fields(Uint8List buf) {
  final out = <_Field>[];
  var i = 0;
  String varint() {
    var small = 0, shift = 0;
    BigInt? big;
    while (true) {
      if (i >= buf.length) throw const FormatException('truncated varint');
      final b = buf[i++];
      if (big == null && shift < 49) {
        small |= (b & 0x7f) << shift;
      } else {
        big ??= BigInt.from(small);
        big |= BigInt.from(b & 0x7f) << shift;
      }
      shift += 7;
      if (b & 0x80 == 0) return (big ?? BigInt.from(small)).toString();
    }
  }

  while (i < buf.length) {
    final key = int.parse(varint());
    final number = key >> 3, wire = key & 7;
    switch (wire) {
      case 0:
        out.add(_Field(number, wire, value: varint()));
      case 1 || 5:
        final len = wire == 1 ? 8 : 4;
        if (i + len > buf.length) throw const FormatException('truncated field');
        out.add(_Field(number, wire, bytes: Uint8List.sublistView(buf, i, i + len)));
        i += len;
      case 2:
        final len = int.parse(varint());
        if (i + len > buf.length) throw const FormatException('truncated field');
        out.add(_Field(number, wire, bytes: Uint8List.sublistView(buf, i, i + len)));
        i += len;
      default:
        throw FormatException('wire type $wire');
    }
  }
  return out;
}

/// Varints of a repeated field, packed (wire 2) or one field each.
List<String> _repeatedVarints(List<_Field> fs, int number) {
  final out = <String>[];
  for (final f in fs.where((f) => f.number == number)) {
    if (f.wire == 0) {
      out.add(f.value!);
    } else if (f.wire == 2) {
      // A packed run is varints back to back: give each a field-1 key.
      final b = BytesBuilder();
      for (final byte in f.bytes!) {
        if (b.isEmpty || (b.toBytes().last & 0x80) == 0) b.addByte(0x08);
        b.addByte(byte);
      }
      out.addAll(_fields(b.toBytes()).map((x) => x.value!));
    }
  }
  return out;
}

bool _gzipped(Uint8List bytes) => bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

Uint8List _unzip(Uint8List bytes) =>
    _gzipped(bytes) ? Uint8List.fromList(const GZipDecoder().decodeBytes(bytes)) : bytes;

/// A Tachiyomi/Mihon backup rather than a Paperback one (a zip).
bool isTachiyomiBackup(Uint8List bytes) => _gzipped(bytes);

_Field? _first(List<_Field> fs, int number, int wire) =>
    fs.where((f) => f.number == number && f.wire == wire).firstOrNull;

class TachiyomiBackupParser {
  static PaperbackBackup parse(Uint8List bytes) {
    final top = _fields(_unzip(bytes));

    final sourceNames = <String, String>{};
    for (final f in top.where((f) => f.number == 101 && f.wire == 2)) {
      final s = _fields(f.bytes!);
      final id = _first(s, 2, 0);
      if (id != null) {
        final sid = _signed(id.value!);
        sourceNames[sid] = _first(s, 1, 2)?.asText ?? 'Source $sid';
      }
    }
    final categoryByOrder = <String, String>{};
    for (final f in top.where((f) => f.number == 2 && f.wire == 2)) {
      final c = _fields(f.bytes!);
      final name = _first(c, 1, 2)?.asText ?? '';
      if (name.isNotEmpty) categoryByOrder[_first(c, 2, 0)?.value ?? '0'] = name;
    }

    final titles = <PaperbackTitle>[];
    final progress = <String, List<PaperbackChapterProgress>>{};
    for (final f in top.where((f) => f.number == 1 && f.wire == 2)) {
      final m = _fields(f.bytes!);
      // Absent means the default, which is "in the library".
      if (_first(m, 100, 0)?.asInt == 0) continue;
      final source = _first(m, 1, 0);
      final url = _first(m, 2, 2)?.asText ?? '';
      final title = _first(m, 3, 2)?.asText ?? '';
      if (source == null || title.isEmpty) continue;
      final sourceId = _signed(source.value!);

      final chapters = [
        for (final c in m.where((x) => x.number == 16 && x.wire == 2))
          () {
            final cf = _fields(c.bytes!);
            final n = _first(cf, 9, 5);
            return PaperbackChapterProgress(
              chapNum: n == null
                  ? -1
                  : ByteData.sublistView(n.bytes!).getFloat32(0, Endian.little).toDouble(),
              completed: _first(cf, 4, 0)?.asInt == 1,
            );
          }(),
      ];
      final key = '$sourceId|$url';
      progress[key] = chapters;
      titles.add(PaperbackTitle(
        libraryId: key,
        primaryTitle: title,
        tabs: [for (final o in _repeatedVarints(m, 17)) ?categoryByOrder[o]],
        sources: [
          PaperbackSource(
            sourceUuid: key,
            sourceId: sourceNames[sourceId] ?? 'Source $sourceId',
            paperbackMangaId: url,
            chapterCount: chapters.length,
            readCount: chapters.where((c) => c.completed).length,
            suwayomiSourceId: sourceId,
            url: url,
          ),
        ],
      ));
    }
    return PaperbackBackup(titles: titles, progressBySourceManga: progress);
  }
}

/// Where to download a repo's index from. The protobuf index replaced the
/// JSON one (which now only says "update your app"), and a github.com
/// `/raw/` link redirects without the CORS header a web build needs, so it
/// goes to raw.githubusercontent.com directly.
String repoIndexUrl(String indexUrl) {
  var url = indexUrl.replaceFirst(RegExp(r'index(\.min)?\.json$'), 'index.pb');
  final gh = RegExp(r'^https://github\.com/([^/]+)/([^/]+)/raw/(.+)$').firstMatch(url);
  if (gh != null) url = 'https://raw.githubusercontent.com/${gh[1]}/${gh[2]}/${gh[3]}';
  return url;
}

/// Extension packages (eu.kanade.tachiyomi.extension...) that provide
/// [sourceIds], from an extension repo's `index.pb` (gzipped protobuf, as
/// Keiyoushi publishes it). Walks the messages without a schema: a source
/// belongs to the nearest enclosing message naming a package.
Map<String, String> extensionsForSources(Uint8List indexPb, Set<String> sourceIds) {
  final found = <String, String>{};
  final printable = RegExp(r'^[\x20-\x7e]+$');

  void walk(Uint8List buf, String? pkg, int depth) {
    List<_Field> fs;
    try {
      fs = _fields(buf);
    } on FormatException {
      return;
    }
    final here = fs
            .where((f) => f.wire == 2)
            .map((f) => _utf8(f.bytes!))
            .where((t) => t.startsWith('eu.kanade.tachiyomi.extension.'))
            .firstOrNull ??
        pkg;
    if (here != null) {
      for (final f in fs) {
        final id = switch (f.wire) { 0 => _signed(f.value!), 2 => _utf8(f.bytes!), _ => null };
        if (id != null && sourceIds.contains(id)) found.putIfAbsent(id, () => here);
      }
    }
    if (depth >= 6) return;
    for (final f in fs.where((f) => f.wire == 2 && f.bytes!.length > 2)) {
      if (printable.hasMatch(_utf8(f.bytes!))) continue; // plain text, not a message
      walk(f.bytes!, here, depth + 1);
    }
  }

  walk(_unzip(indexPb), null, 0);
  return found;
}
