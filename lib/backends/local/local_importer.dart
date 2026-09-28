import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

import 'local_library_store.dart';

/// Thrown when a picked file can't be imported - message is written to be
/// shown directly to the user.
class ImportException implements Exception {
  final String message;
  const ImportException(this.message);
  @override
  String toString() => message;
}

const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

/// Archive extensions the importer accepts. ZIP-based ones work everywhere;
/// the rest (RAR, 7z, tar) are unpacked by the OS's libarchive `tar`, so only
/// on desktop - see [canUnpackNonZipArchives].
const importableArchiveExtensions = [
  'cbz', 'zip', 'cbr', 'rar', 'cb7', '7z', 'cbt', 'tar',
];

bool _isImage(String path) {
  final lower = path.toLowerCase();
  // macOS zips carry resource-fork shadows ("__MACOSX/._001.jpg") that look
  // like pages but aren't images.
  if (lower.contains('__macosx')) return false;
  final name = lower.split(RegExp(r'[/\\]')).last;
  if (name.startsWith('._')) return false;
  return _imageExtensions.any(lower.endsWith);
}

/// Natural-ish sort so "page2.jpg" comes before "page10.jpg" - archive tools
/// don't agree on zero-padding, and plain string sort gets that wrong.
int _compareNames(String a, String b) {
  final ax = RegExp(r'(\d+)|(\D+)').allMatches(a).map((m) => m.group(0)!);
  final bx = RegExp(r'(\d+)|(\D+)').allMatches(b).map((m) => m.group(0)!);
  final ai = ax.iterator, bi = bx.iterator;
  while (true) {
    final aHas = ai.moveNext(), bHas = bi.moveNext();
    if (!aHas || !bHas) return (aHas ? 1 : 0) - (bHas ? 1 : 0);
    final an = int.tryParse(ai.current), bn = int.tryParse(bi.current);
    final cmp = (an != null && bn != null)
        ? an.compareTo(bn)
        : ai.current.compareTo(bi.current);
    if (cmp != 0) return cmp;
  }
}

String _baseName(String path) =>
    path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

/// A tidy chapter/volume title guessed from a filename - strips the
/// extension and the "(2024) (Digital) (Group)" bracket tags that scene
/// releases tack on, since those belong in metadata, not the title shown.
String titleFromFileName(String fileName) {
  var name = fileName;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? fileName : name;
}

bool _startsWith(List<int> head, List<int> magic) =>
    head.length >= magic.length &&
    Iterable.generate(magic.length).every((i) => head[i] == magic[i]);

bool _isZip(List<int> head) => _startsWith(head, [0x50, 0x4B]); // "PK"
bool _isRar(List<int> head) => _startsWith(head, [0x52, 0x61, 0x72, 0x21]);

typedef _PageWriter = Future<void> Function(String bookId, int pageIndex);

/// Writes one chapter's pages (via [writePage], one at a time so a huge book
/// never sits in memory whole) plus its book record, filed under a series
/// matching [seriesTitle] (reusing an existing one with the same title,
/// case-insensitively, or creating one). Every import path ends up here.
Future<String> _finishImport({
  required LocalLibraryStore store,
  required String chapterTitle,
  required int pageCount,
  required _PageWriter writePage,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  if (pageCount == 0) {
    throw const ImportException('No image pages found.');
  }

  const uuid = Uuid();
  final bookId = uuid.v4();
  // Pages before any record: a failure part-way leaves nothing half-imported
  // in the library.
  try {
    for (var i = 0; i < pageCount; i++) {
      await writePage(bookId, i);
    }
  } catch (_) {
    await store.deletePages(bookId, pageCount);
    rethrow;
  }

  final title = titleFromFileName(seriesTitle ?? chapterTitle);
  final existing = store
      .listSeries()
      .where((s) => s.title.toLowerCase() == title.toLowerCase());
  final seriesId = existing.isNotEmpty ? existing.first.id : uuid.v4();
  if (existing.isEmpty) {
    await store.putSeries(LocalSeriesRecord(
      id: seriesId,
      title: title,
      addedAt: DateTime.now(),
    ));
  }

  final existingBooks = store.listBooksForSeries(seriesId);
  await store.putBook(LocalBookRecord(
    id: bookId,
    seriesId: seriesId,
    title: titleFromFileName(chapterTitle),
    number: chapterNumber ?? '${existingBooks.length + 1}',
    pageCount: pageCount,
    addedAt: DateTime.now(),
  ));

  return bookId;
}

Future<String> _importArchiveEntries(
  Archive archive, {
  required LocalLibraryStore store,
  required String fileName,
  String? seriesTitle,
  String? chapterNumber,
}) {
  final images = archive.files.where((f) => f.isFile && _isImage(f.name)).toList()
    ..sort((a, b) => _compareNames(a.name, b.name));
  if (images.isEmpty) {
    throw const ImportException('No image pages found inside this file.');
  }
  return _finishImport(
    store: store,
    chapterTitle: fileName,
    pageCount: images.length,
    writePage: (bookId, i) => store.putPage(bookId, i, images[i].content),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// Imports a comic archive from in-memory [bytes] - the web path, where a
/// picked file has no filesystem path. ZIP-based only (CBZ/ZIP); desktop
/// uses [importArchiveFile], which also handles RAR/7z.
Future<String> importArchive({
  required LocalLibraryStore store,
  required String fileName,
  required Uint8List bytes,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  // Check the real format before decoding - ZipDecoder can decode garbage
  // leniently as an empty archive instead of throwing, which would surface
  // as a confusing "no pages found" for what's actually a RAR file.
  if (!_isZip(bytes)) {
    throw ImportException(_isRar(bytes)
        ? "This is a RAR-based CBR file. It can be imported from the desktop "
            "app - this device can't unpack RAR archives."
        : "Couldn't read this as a comic archive.");
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ImportException("Couldn't read this as a comic archive.");
  }
  return _importArchiveEntries(
    archive,
    store: store,
    fileName: fileName,
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// Whether this platform can unpack RAR/7z/tar archives (via the OS's
/// libarchive-based `tar`). iOS and Android can't run external programs.
bool get canUnpackNonZipArchives => !kIsWeb && _systemTar() != null;

String? _systemTar() {
  if (Platform.isWindows) {
    // Windows 10 1803+ ships libarchive's bsdtar as tar.exe, which reads
    // RAR (including RAR5) and 7z as well as tar.
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final tar = '$root\\System32\\tar.exe';
    return File(tar).existsSync() ? tar : null;
  }
  if (Platform.isMacOS) {
    return File('/usr/bin/bsdtar').existsSync() ? '/usr/bin/bsdtar' : '/usr/bin/tar';
  }
  if (Platform.isLinux) {
    // GNU tar (the usual /usr/bin/tar) can't read RAR - only bsdtar can.
    for (final path in ['/usr/bin/bsdtar', '/bin/bsdtar']) {
      if (File(path).existsSync()) return path;
    }
  }
  return null;
}

/// Imports a comic archive straight from disk - the desktop/mobile path.
/// ZIPs are read entry by entry without loading the whole file; anything
/// else (RAR-based CBR, 7z, tar) is unpacked with the OS's `tar` into a
/// temp folder first.
Future<String> importArchiveFile({
  required LocalLibraryStore store,
  required String path,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  final fileName = _baseName(path);
  final raf = await File(path).open();
  final List<int> head;
  try {
    head = await raf.read(8);
  } finally {
    await raf.close();
  }

  if (_isZip(head)) {
    final input = InputFileStream(path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } catch (_) {
        throw const ImportException("Couldn't read this as a comic archive.");
      }
      return await _importArchiveEntries(
        archive,
        store: store,
        fileName: fileName,
        seriesTitle: seriesTitle,
        chapterNumber: chapterNumber,
      );
    } finally {
      await input.close();
    }
  }

  final tar = _systemTar();
  if (tar == null) {
    throw ImportException(_isRar(head)
        ? "This is a RAR-based CBR file. It can be imported from the desktop "
            "app - this device can't unpack RAR archives."
        : "Couldn't read this as a comic archive.");
  }

  final temp = await Directory.systemTemp.createTemp('shaddai_import_');
  try {
    // Argument list, no shell - the path is never interpreted. libarchive
    // refuses absolute and "../" entry paths by default, so a hostile
    // archive can't write outside [temp].
    final result = await Process.run(tar, ['-xf', path, '-C', temp.path]);
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim().split('\n').first;
      throw ImportException("Couldn't unpack this archive"
          '${detail.isEmpty ? '' : ': $detail'}');
    }
    return await _importImagesIn(
      temp,
      store: store,
      chapterTitle: fileName,
      seriesTitle: seriesTitle,
      chapterNumber: chapterNumber,
      // The unpacked copies are ours to consume - move rather than copy, so
      // a multi-gigabyte omnibus doesn't briefly need twice the disk.
      move: true,
      emptyMessage: 'No image pages found inside this file.',
    );
  } finally {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Leftover temp files are harmless; the OS cleans its temp dir.
    }
  }
}

Future<String> _importImagesIn(
  Directory dir, {
  required LocalLibraryStore store,
  required String chapterTitle,
  String? seriesTitle,
  String? chapterNumber,
  bool move = false,
  String emptyMessage = 'No image files found in that folder.',
}) async {
  final entries = await dir
      .list(recursive: true)
      .where((e) => e is File && _isImage(e.path))
      .cast<File>()
      .toList();
  entries.sort((a, b) => _compareNames(a.path, b.path));
  if (entries.isEmpty) throw ImportException(emptyMessage);

  return _finishImport(
    store: store,
    chapterTitle: chapterTitle,
    pageCount: entries.length,
    writePage: (bookId, i) =>
        store.putPageFromFile(bookId, i, entries[i], move: move),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// Imports every image file directly inside (or nested under) [folderPath]
/// as one chapter - the folder-of-loose-pages layout some scanlation/download
/// tools use instead of a zip. Desktop/mobile only (no filesystem on web);
/// the caller routes web users to [importLooseFiles] instead.
Future<String> importFolder({
  required LocalLibraryStore store,
  required String folderPath,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  final dir = Directory(folderPath);
  if (!await dir.exists()) {
    throw const ImportException("That folder couldn't be found.");
  }
  return _importImagesIn(
    dir,
    store: store,
    chapterTitle: _baseName(folderPath),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// One entry from a multi-file picker: a filename (for sort order and the
/// guessed title) plus its already-read bytes. Used for loose image files
/// the user selects directly - the one folder-of-images path that also
/// works on web, since it goes through the file picker rather than a real
/// filesystem path.
class PickedImageFile {
  final String name;
  final Uint8List bytes;
  const PickedImageFile(this.name, this.bytes);
}

Future<String> importLooseFiles({
  required LocalLibraryStore store,
  required List<PickedImageFile> files,
  required String chapterTitle,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  final images = files.where((f) => _isImage(f.name)).toList()
    ..sort((a, b) => _compareNames(a.name, b.name));
  if (images.isEmpty) {
    throw const ImportException('No image files were selected.');
  }
  return _finishImport(
    store: store,
    chapterTitle: chapterTitle,
    pageCount: images.length,
    writePage: (bookId, i) => store.putPage(bookId, i, images[i].bytes),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// File extension matching an image's actual format (pages are stored
/// without one), so an exported CBZ opens correctly in other readers.
String _imageExtension(List<int> head) {
  if (_startsWith(head, [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (_startsWith(head, [0x47, 0x49, 0x46])) return 'gif';
  if (_startsWith(head, [0x42, 0x4D])) return 'bmp';
  if (head.length >= 12 &&
      _startsWith(head, [0x52, 0x49, 0x46, 0x46]) &&
      String.fromCharCodes(head.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  return 'jpg';
}

String _pageName(int index, List<int> head) =>
    '${(index + 1).toString().padLeft(4, '0')}.${_imageExtension(head)}';

/// Re-zips a previously-imported book's stored pages back into a CBZ, in
/// memory. Fine for web-sized books; on desktop/mobile prefer
/// [exportBookToCbzFile], which streams to disk.
Future<Uint8List> exportBookToCbz(
    LocalLibraryStore store, LocalBookRecord book) async {
  final archive = Archive();
  for (var i = 0; i < book.pageCount; i++) {
    final bytes = await store.getPage(book.id, i);
    if (bytes == null) continue;
    archive.addFile(ArchiveFile(_pageName(i, bytes), bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Writes a book's pages to a CBZ at [outPath] one page at a time, so even a
/// multi-gigabyte book never has to fit in memory. Pages are stored, not
/// re-compressed - they're already compressed images.
Future<void> exportBookToCbzFile(
  LocalLibraryStore store,
  LocalBookRecord book,
  String outPath,
) async {
  final encoder = ZipFileEncoder()..create(outPath, level: 0);
  try {
    for (var i = 0; i < book.pageCount; i++) {
      final file = store.pageFile(book.id, i);
      if (file != null) {
        final raf = await file.open();
        final List<int> head;
        try {
          head = await raf.read(12);
        } finally {
          await raf.close();
        }
        await encoder.addFile(file, _pageName(i, head), 0);
      } else {
        final bytes = await store.getPage(book.id, i);
        if (bytes == null) continue;
        encoder.addArchiveFile(
            ArchiveFile(_pageName(i, bytes), bytes.length, bytes));
      }
    }
  } finally {
    await encoder.close();
  }
}

/// A filesystem-safe version of [name] - strips characters Windows/macOS
/// forbid in file/folder names.
String sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return cleaned.isEmpty ? 'Untitled' : cleaned;
}

/// Exports every book in [seriesId] as one CBZ per chapter, under
/// `<folderPath>/<series title>/<chapter title>.cbz`. Returns the number of
/// files written.
Future<int> exportSeriesToFolder({
  required LocalLibraryStore store,
  required String seriesId,
  required String folderPath,
}) async {
  final series = store.getSeries(seriesId);
  if (series == null) throw const ImportException('Series not found.');
  final books = store.listBooksForSeries(seriesId);
  final dir = Directory('$folderPath/${sanitizeFileName(series.title)}');
  await dir.create(recursive: true);
  for (final book in books) {
    await exportBookToCbzFile(
        store, book, '${dir.path}/${sanitizeFileName(book.title)}.cbz');
  }
  return books.length;
}
