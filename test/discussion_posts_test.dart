import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/stock_price_service.dart';

void main() {
  test(
    'mobile feed preserves Korean titles, dates, counts and current links',
    () {
      final posts = StockPriceService.parseDiscussionPosts(
        jsonEncode({
          'isSuccess': true,
          'result': {
            'posts': [
              {
                'id': '123',
                'title': '삼성전자 전망',
                'writtenAt': '2026-09-16T02:16:00',
                'viewCount': 116,
              },
              {'id': 'broken', 'title': '잘못된 날짜', 'writtenAt': 'invalid'},
              {
                'id': 124,
                'title': '다음 게시글',
                'writtenAt': '2026-09-16T02:15:00',
                'viewCount': '12',
              },
            ],
          },
        }),
        '005930',
      );
      expect(posts.length, 2);
      expect(posts.first.title, '삼성전자 전망');
      expect(posts.first.date, DateTime(2026, 9, 16, 2, 16));
      expect(posts.first.viewCount, 116);
      expect(posts.last.viewCount, 12);
      expect(
        posts.first.mobileReadUrl,
        'https://m.stock.naver.com/domestic/stock/005930/discussion/123',
      );
    },
  );

  test('empty board differs from upstream errors and legacy error HTML', () {
    expect(
      StockPriceService.parseDiscussionPosts(
        '{"isSuccess":true,"result":{"posts":[]}}',
        '005930',
      ),
      isEmpty,
    );
    for (final body in [
      '<html>error</html>',
      '{"isSuccess":false}',
      '{"isSuccess":true,"result":{}}',
    ]) {
      expect(
        () => StockPriceService.parseDiscussionPosts(body, '005930'),
        throwsFormatException,
      );
    }
  });
}
