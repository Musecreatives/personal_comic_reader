/// A friend's own library and reading progress on the shared Suwayomi.
///
/// Suwayomi has one library, so a friend connected through the gateway
/// (suwayomi.shaddaicommunications.com) keeps theirs in the sync service,
/// at `/shaddai/*` on the same address and with the same login. The owner's
/// connection gets no answer there and keeps using Suwayomi's own library.
library;

import 'package:dio/dio.dart';

/// One title in a friend's library. [readThrough] is the last chapter
/// number read, as an import or a finished chapter left it; [readCount]
/// how many chapters that is.
class MemberTitle {
  final int mangaId;
  final String title;
  final String? sourceId;
  final List<String> categories;
  final double? readThrough;
  final int readCount;

  const MemberTitle({
    required this.mangaId,
    required this.title,
    this.sourceId,
    this.categories = const [],
    this.readThrough,
    this.readCount = 0,
  });

  factory MemberTitle.fromJson(Map<String, dynamic> j) => MemberTitle(
        mangaId: (j['mangaId'] as num).toInt(),
        title: j['title'] as String? ?? 'Untitled',
        sourceId: j['sourceId'] as String?,
        categories: [...?(j['categories'] as List?)?.whereType<String>()],
        readThrough: (j['readThrough'] as num?)?.toDouble(),
        readCount: (j['readCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'sourceId': ?sourceId,
        'categories': categories,
        'readThrough': ?readThrough,
        'readCount': readCount,
      };

  /// After finishing chapter [number]: read through the furthest one.
  MemberTitle finished(double number) => MemberTitle(
        mangaId: mangaId,
        title: title,
        sourceId: sourceId,
        categories: categories,
        readThrough: readThrough == null || number > readThrough! ? number : readThrough,
        readCount: readCount + 1,
      );
}

/// A friend's page and read state for one chapter: their own progress
/// record when they've opened it, otherwise read when its number is at or
/// below [readThrough] (how an imported "read up to 186" carries over
/// without a record per chapter). Unnumbered chapters (-1) are never
/// counted read that way.
({bool read, int page}) memberChapterState({
  required double? number,
  required double? readThrough,
  Map<String, dynamic>? record,
}) {
  if (record != null) {
    return (read: record['read'] == true, page: (record['page'] as num?)?.toInt() ?? 0);
  }
  final read = number != null && number >= 0 && readThrough != null && number <= readThrough;
  return (read: read, page: 0);
}

/// The `/shaddai/*` calls. [dio] is the Suwayomi connection's own client,
/// so it carries the same address and login.
class MemberLibraryApi {
  final Dio dio;
  MemberLibraryApi(this.dio);

  /// True for a friend's connection through the gateway, false for anything
  /// that answered otherwise (Suwayomi itself has no such route; the owner
  /// is "owner"). Null when nothing answered, so the caller asks again
  /// rather than settling on owner mode while offline.
  Future<bool?> isMember() async {
    try {
      final res = await dio.get<dynamic>('/shaddai/me');
      final data = res.data;
      return data is Map && data['role'] == 'member';
    } on DioException catch (e) {
      return e.type == DioExceptionType.badResponse ? false : null;
    }
  }

  Future<List<MemberTitle>> library() async {
    final res = await dio.get<Map<String, dynamic>>('/shaddai/library');
    return [
      for (final t in (res.data!['titles'] as List).cast<Map<String, dynamic>>())
        if (t['mangaId'] is num) MemberTitle.fromJson(t),
    ];
  }

  Future<void> put(MemberTitle t) =>
      dio.put<dynamic>('/shaddai/library/${t.mangaId}', data: t.toJson());

  Future<void> remove(int mangaId) => dio.delete<dynamic>('/shaddai/library/$mangaId');

  /// Chapter id -> {chapterId, mangaId, page, read}, for [mangaIds].
  Future<Map<int, Map<String, dynamic>>> progress(Iterable<int> mangaIds) async {
    final res = await dio.get<Map<String, dynamic>>('/shaddai/progress',
        queryParameters: {'manga_ids': mangaIds.join(',')});
    return {
      for (final e in (res.data!['chapters'] as Map<String, dynamic>).entries)
        int.parse(e.key): e.value as Map<String, dynamic>,
    };
  }

  Future<void> saveProgress(List<({int chapterId, int mangaId, int page, bool read})> items) =>
      dio.put<dynamic>('/shaddai/progress', data: [
        for (final p in items)
          {'chapterId': p.chapterId, 'mangaId': p.mangaId, 'page': p.page, 'read': p.read},
      ]);
}
