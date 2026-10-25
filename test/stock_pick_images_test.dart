import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/models/stock_pick.dart';

void main() {
  StockPick pick({String? legacy, List<String> images = const []}) => StockPick(
    id: 'pick',
    ticker: 'TEST',
    name: 'Test',
    buyPrice: 1,
    targetPrice: 2,
    reason: 'reason',
    category: '',
    isPremium: false,
    createdAt: DateTime(2026),
    imageUrl: legacy,
    imageUrls: images,
  );
  test('legacy cover remains visible', () {
    expect(pick(legacy: 'old.png').allImageUrls, ['old.png']);
  });
  test('multiple images preserve order without duplicate cover', () {
    final value = pick(legacy: 'one.png', images: ['one.png', 'two.png']);
    expect(value.allImageUrls, ['one.png', 'two.png']);
    expect(value.toFirestore()['imageUrls'], ['one.png', 'two.png']);
  });
  test('removing every image clears both fields on update', () {
    final data = pick().toFirestore();
    expect(data['imageUrl'], isNull);
    expect(data['imageUrls'], isEmpty);
  });
}
