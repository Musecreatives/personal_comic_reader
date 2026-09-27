import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

bool _isImage(String name) {
  final lower = name.toLowerCase();
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

/// Writes one chapter (a sorted, already-resolved set of page bytes) plus
/// its book record, filed under a series matching [seriesTitle] (reusing an
/// existing one with the same title, case-insensitively, or creating one).
/// Shared by every import path - a ZIP's internal files, a folder's files
/// on disk, and loose files the user multi-selected all end up here.
Future<String> _finishImport({
  required LocalLibraryStore store,
  required String chapterTitle,
  required List<Uint8List> pages,
  String? seriesTitle,
  String? chapterNumber,
}) async {
  if (pages.isEmpty) {
    throw const ImportException('No image pages found.');
  }

  const uuid = Uuid();
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

  final bookId = uuid.v4();
  for (var i = 0; i < pages.length; i++) {
    await store.putPage(bookId, i, pages[i]);
  }

  final existingBooks = store.listBooksForSeries(seriesId);
  await store.putBook(LocalBookRecord(
    id: bookId,
    seriesId: seriesId,
    title: titleFromFileName(chapterTitle),
    number: chapterNumber ?? '${existingBooks.length + 1}',
    pageCount: pages.length,
    addedAt: DateTime.now(),
  ));

  return bookId;
}

/// Unzips [bytes] (a CBZ/ZIP/CBC file) and stores each image page.
///
/// True CBR (RAR-compressed) files aren't supported - there's no
/// actively-maintained pure-Dart RAR decoder - so this throws
/// [ImportException] for anything that isn't actually a ZIP underneath
/// (some ".cbr" files are mislabeled ZIPs and import fine anyway).
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
  if (bytes.length >= 4 && bytes[0] == 0x52 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21) {
    throw const ImportException(
        "This is a real RAR-based CBR file, which isn't supported yet - "
        're-save or convert it to CBZ (a ZIP archive) first.');
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.cbr') || lower.endsWith('.rar')) {
      throw const ImportException(
          "This is a real RAR-based CBR file, which isn't supported yet - "
          're-save or convert it to CBZ (a ZIP archive) first.');
    }
    throw const ImportException("Couldn't read this as a comic archive.");
  }

  final imageFiles = archive.files.where((f) => f.isFile && _isImage(f.name)).toList()
    ..sort((a, b) => _compareNames(a.name, b.name));
  if (imageFiles.isEmpty) {
    throw const ImportException('No image pages found inside this file.');
  }

  return _finishImport(
    store: store,
    chapterTitle: fileName,
    pages: imageFiles
        .map((f) => Uint8List.fromList(f.content as List<int>))
        .toList(),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}

/// Reads every image file directly inside (or nested under) [folderPath] on
/// disk and imports them as one chapter - the folder-of-loose-pages layout
/// some scanlation/download tools use instead of a zip. Desktop/mobile only
/// (there's no real filesystem path to read from in a browser); the caller
/// is expected to route web users to [importLooseFiles] instead.
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

  final entries = await dir
      .list(recursive: true)
      .where((e) => e is File && _isImage(e.path))
      .cast<File>()
      .toList();
  entries.sort((a, b) => _compareNames(a.path, b.path));
  if (entries.isEmpty) {
    throw const ImportException('No image files found in that folder.');
  }

  final pages = await Future.wait(entries.map((f) => f.readAsBytes()));
  final folderName = folderPath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
  return _finishImport(
    store: store,
    chapterTitle: folderName,
    pages: pages.map(Uint8List.fromList).toList(),
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
    pages: images.map((f) => f.bytes).toList(),
    seriesTitle: seriesTitle,
    chapterNumber: chapterNumber,
  );
}
