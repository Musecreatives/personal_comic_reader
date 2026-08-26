/// A local-only, user-made shelf that can pull series from any configured
/// server at once (6d Collections). Never synced - if you switch devices,
/// it doesn't come with you.
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
