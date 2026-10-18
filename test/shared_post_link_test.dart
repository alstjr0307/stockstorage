import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/models/shared_post_link.dart';

void main() {
  test('shared post URLs preserve the document ID', () {
    for (final id in ['abc123', 'post-with_underscore', '한글 글']) {
      final link = SharedPostLink(id).toUri();
      expect(link.host, SharedPostLink.host);
      expect(SharedPostLink.parse(link)?.postId, id);
    }
  });

  test('untrusted, malformed and non-post URLs are rejected', () {
    for (final url in [
      'https://evil.test/post/abc',
      'http://stockstorage-13828.web.app/post/abc',
      'https://stockstorage-13828.web.app/post/',
      'https://stockstorage-13828.web.app/post/abc/extra',
      'https://stockstorage-13828.web.app/post/a%2Fb',
      'https://stockstorage-13828.web.app/post/a%5Cb',
      'https://stockstorage-13828.web.app/post/%00',
      'https://stockstorage-13828.web.app/pick/abc',
    ]) {
      expect(SharedPostLink.parse(Uri.parse(url)), isNull, reason: url);
    }
  });

  test('web entry preserves post ID and rejects invalid IDs', () {
    expect(
      SharedPostLink.parse(
        Uri.https('stockstorage-web.web.app', '/', {'postId': 'abc123'}),
        webEntry: true,
      )?.postId,
      'abc123',
    );
    for (final id in ['', '.', '..', 'a/b', 'a\\b', '\n']) {
      expect(
        SharedPostLink.parse(
          Uri.https('stockstorage-web.web.app', '/', {'postId': id}),
          webEntry: true,
        ),
        isNull,
      );
    }
  });
}
