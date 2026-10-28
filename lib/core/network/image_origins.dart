/// Login headers only ever go to the user's own servers. A cover can be a
/// link to an outside site (a cover picked from AniList or MangaDex), and
/// sending a server's login with it would hand that login to the site.
///
/// Every server's address is registered when its backend is built
/// (`buildBackend`); [imageHeadersFor] drops the headers for anything else.
final Set<String> _serverOrigins = {};

void trustImageOrigin(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri != null && uri.hasScheme) _serverOrigins.add(uri.origin);
}

/// [headers] when [url] is on a registered server, otherwise none. The
/// comparison is on the full origin (scheme, host and port), so a
/// look-alike host such as `myserver.evil.example` gets nothing.
Map<String, String> imageHeadersFor(String url, Map<String, String> headers) {
  if (headers.isEmpty) return headers;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return const {};
  return _serverOrigins.contains(uri.origin) ? headers : const {};
}
