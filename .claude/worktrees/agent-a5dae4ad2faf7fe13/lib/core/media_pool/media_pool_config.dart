/// A WebDAV endpoint (e.g. a Nextcloud "external storage" mount) that lands
/// directly in a server-side library folder - uploading here is real backup,
/// not just a copy, since whatever reads that folder (Suwayomi's local
/// source, Komga, etc.) picks the files up on its own.
class MediaPoolConfig {
  final String baseUrl;
  final String username;
  final String password;

  const MediaPoolConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
}
