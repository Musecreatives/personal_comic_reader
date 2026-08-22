import 'dart:typed_data';

import 'models.dart';

/// Server type a [ReaderBackend] talks to.
enum ServerType { komga, kavita }

/// Everything the UI needs to know about a configured server.
///
/// This is what gets persisted (minus [password], which lives in secure
/// storage separately) and what a [ReaderBackend] is constructed from.
class ServerConfig {
  final String id;
  final String name;
  final ServerType type;
  final String baseUrl;
  final String username;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.username,
  });

  ServerConfig copyWith({
    String? name,
    ServerType? type,
    String? baseUrl,
    String? username,
  }) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'baseUrl': baseUrl,
        'username': username,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        type: ServerType.values.byName(json['type'] as String),
        baseUrl: json['baseUrl'] as String,
        username: json['username'] as String,
      );
}

/// Server-agnostic interface the UI programs against.
///
/// Every server type (Komga, Kavita, ...) gets one implementation. The UI
/// must never talk to dio / an HTTP client directly - it only ever sees
/// this interface via a Riverpod provider.
abstract class ReaderBackend {
  ServerConfig get config;

  /// Authenticates against the server. For basic-auth backends (Komga) this
  /// may just validate credentials; for token backends (Kavita) this
  /// obtains and stores the JWT.
  Future<void> authenticate();

  Future<List<Library>> listLibraries();

  Future<PagedResult<Series>> listSeries({
    String? libraryId,
    int page = 0,
    int size = 20,
    SeriesSort sort = SeriesSort.title,
    SortDirection direction = SortDirection.asc,
    bool unreadOnly = false,
    String? search,
  });

  Future<Series> getSeries(String id);

  Future<List<Book>> listBooks(String seriesId);

  Future<Book> getBook(String id);

  /// Direct, authenticated URL for a given page. Some backends (Kavita)
  /// need an API key embedded in the query string; others (Komga) rely on
  /// the dio interceptor to attach a header, in which case a bare URL is
  /// fine here and [fetchPage] should be preferred for actually loading
  /// bytes since it goes through the authenticated dio client.
  Future<Uri> pageUri(String bookId, int pageIndex);

  Future<Uint8List> fetchPage(String bookId, int pageIndex);

  Future<void> updateProgress(
    String bookId, {
    required int page,
    bool completed = false,
  });

  Future<List<Series>> continueReading();

  Future<List<Book>> recentlyAdded();

  Future<List<Collection>> listCollections();

  Future<List<ReadList>> listReadLists();

  String thumbnailUrlForSeries(String seriesId);

  String thumbnailUrlForBook(String bookId);

  /// HTTP headers needed to load images (thumbnails, pages) fetched
  /// directly by URL rather than through [fetchPage] - e.g. via
  /// CachedNetworkImage. Backends that put auth in the URL itself
  /// (Kavita's `apiKey` query param) can return an empty map.
  Map<String, String> get imageHeaders;
}

/// Thrown by backend methods that are intentionally not implemented yet
/// (e.g. the Kavita stub in Phase 1).
class BackendNotImplemented implements Exception {
  final String feature;
  const BackendNotImplemented(this.feature);

  @override
  String toString() => 'Not implemented yet: $feature';
}
