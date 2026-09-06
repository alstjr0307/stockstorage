import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/stock_price_service.dart';

void main() {
  test('fetchMaxPain AAPL', tags: ['network'], () async {
    final r = await StockPriceService.fetchMaxPain('AAPL', 'US');
    expect(r, isNotNull);
    print('MaxPain: \$${r!.maxPain}');
    print('현재가: ${r.underlyingPrice}');
    print('만기: ${r.expiration}');
    print('콜 OI: ${r.totalCallOi}, 풋 OI: ${r.totalPutOi}, P/C: ${r.putCallRatio?.toStringAsFixed(2)}');
    print('행사가 수: ${r.strikes.length}');
    expect(r.maxPain, greaterThan(0));
    expect(r.strikes, isNotEmpty);
  });

  test('fetchMaxPain 한국주식은 null', tags: ['network'], () async {
    final r = await StockPriceService.fetchMaxPain('005930', 'KS');
    expect(r, isNull);
  });
}
