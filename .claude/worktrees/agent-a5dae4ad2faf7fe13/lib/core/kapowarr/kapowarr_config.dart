/// Connection details for the (single, optional) Kapowarr instance.
///
/// Kapowarr is not a [ReaderBackend] - it's an acquisition tool, not a
/// source of readable content - so it gets its own lightweight config
/// separate from the server list.
class KapowarrConfig {
  final String baseUrl;
  final String apiKey;

  const KapowarrConfig({required this.baseUrl, required this.apiKey});
}
