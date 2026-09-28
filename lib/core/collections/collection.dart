// Unit separator: can't appear in a server key (type|url) or a series id
// (plain ids, or OPDS feed URLs).
const _entrySep = '\u001F';

/// A collection entry for [seriesId] on the server with [serverKey]
/// ([ServerConfig.portableKey], so it resolves on every synced device -
/// series ids are only unique within one server).
String collectionEntry(String serverKey, String seriesId) =>
    '$serverKey$_entrySep$seriesId';

/// Splits an entry back up. Entries saved before servers were recorded are
/// a bare series id: [serverKey] is null, meaning "the active server".
({String? serverKey, String seriesId}) parseCollectionEntry(String entry) {
  final i = entry.indexOf(_entrySep);
  if (i < 0) return (serverKey: null, seriesId: entry);
  return (serverKey: entry.substring(0, i), seriesId: entry.substring(i + 1));
}

/// A user-made shelf that can pull series from any configured server at
/// once (6d Collections). Synced between devices signed in to the same
/// account. [seriesIds] holds [collectionEntry] values.
class LocalCollection {
  final String id;
  final String name;
  final List<String> seriesIds;
  final DateTime createdAt;

  const LocalCollection({
    required this.id,
    required this.name,
    required this.seriesIds,
    required this.createdAt,
  });

  LocalCollection copyWith({String? name, List<String>? seriesIds}) => LocalCollection(
        id: id,
        name: name ?? this.name,
        seriesIds: seriesIds ?? this.seriesIds,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seriesIds': seriesIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LocalCollection.fromJson(Map<String, dynamic> json) => LocalCollection(
        id: json['id'] as String,
        name: json['name'] as String,
        seriesIds: (json['seriesIds'] as List).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
