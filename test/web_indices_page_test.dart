import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/stock_price_service.dart';
import 'package:stockstorage/web/web_indices_page.dart';

void main() {
  testWidgets(
    'indices appear independently and failed quotes can be refreshed',
    (tester) async {
      final pending = <String, Completer<PriceResult?>>{};
      await tester.pumpWidget(
        MaterialApp(
          home: WebIndicesPage(
            fetchPrice: (ticker, market) {
              final request = Completer<PriceResult?>();
              pending[ticker] = request;
              return request.future;
            },
          ),
        ),
      );
      pending['^KS11']!.complete(
        const PriceResult(
          price: 2500.5,
          currency: 'KRW',
          change: 25,
          changeRate: 1.01,
        ),
      );
      await tester.pump();
      expect(find.text('2,500.50'), findsOneWidget);
      expect(find.text('+1.01%'), findsOneWidget);
      expect(find.text('시세 불러오는 중…'), findsWidgets);
      for (final request in pending.values) {
        if (!request.isCompleted) request.completeError(StateError('offline'));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('시세를 불러오지 못했어요'), findsWidgets);
      await tester.tap(find.byTooltip('시세 새로고침'));
      await tester.pump();
      for (final request in pending.values) {
        request.complete(
          const PriceResult(
            price: 1234,
            currency: 'USD',
            change: 0,
            changeRate: 0,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('1,234.00'), findsWidgets);
      expect(find.textContaining('시세를 불러오지 못했어요'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
