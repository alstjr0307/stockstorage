import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/models/shared_stock_link.dart';

void main() {
  test('Korean stock and name survive a public link roundtrip', () {
    const stock = SharedStockLink(market: 'KS', ticker: '005930', name: '삼성전자');
    final uri = stock.toUri(source: 'ai_result');
    final parsed = SharedStockLink.parse(uri)!;
    expect(parsed.ticker, '005930');
    expect(parsed.name, '삼성전자');
    expect(uri.queryParameters['utm_source'], 'ai_result');
    expect(uri.queryParameters.keys, isNot(contains('uid')));
  });
  test(
    'rejects unrelated hosts, malformed stocks and recommendation routes',
    () {
      for (final url in [
        'https://evil.test/stock/KS/005930',
        'http://stockstorage-13828.web.app/stock/KS/005930',
        'https://stockstorage-13828.web.app/stock/KS/5930',
        'https://stockstorage-13828.web.app/stock/US/../../users',
        'https://stockstorage-13828.web.app/pick/005930',
      ]) {
        expect(SharedStockLink.parse(Uri.parse(url)), isNull, reason: url);
      }
    },
  );
  test('web entry resumes the exact market and class-share ticker', () {
    final stock = SharedStockLink.parse(
      Uri.parse(
        'https://stockstorage-web.web.app/?market=US&ticker=BRK.B&name=Berkshire',
      ),
      webEntry: true,
    )!;
    expect(stock.market, 'US');
    expect(stock.ticker, 'BRK.B');
  });
}
