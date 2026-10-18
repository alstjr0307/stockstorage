/// A public community post link, without author or viewer identifiers.
class SharedPostLink {
  const SharedPostLink(this.postId);

  final String postId;
  static const host = 'stockstorage-13828.web.app';

  static bool isValidId(String id) =>
      id.isNotEmpty &&
      id.length <= 1500 &&
      id != '.' &&
      id != '..' &&
      !RegExp(r'[/\\\x00-\x1f]').hasMatch(id);

  Uri toUri() =>
      Uri(scheme: 'https', host: host, pathSegments: ['post', postId]);

  static SharedPostLink? parse(Uri uri, {bool webEntry = false}) {
    if (uri.scheme != 'https' ||
        uri.host != (webEntry ? 'stockstorage-web.web.app' : host)) {
      return null;
    }
    final parts = uri.pathSegments;
    final id = webEntry
        ? uri.queryParameters['postId']
        : (parts.length == 2 && parts[0] == 'post' ? parts[1] : null);
    return id != null && isValidId(id) ? SharedPostLink(id) : null;
  }
}
