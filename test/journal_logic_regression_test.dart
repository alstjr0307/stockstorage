import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/screens/journal_chart_screen.dart';
import 'package:stockstorage/screens/trading_journal_screen.dart';
import 'package:stockstorage/services/firestore_service.dart';
import 'journal_v2_test.dart' show trade;

class _NoBackend implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backend access');
}

void main() {
  test(
    'chart uses moving-average realized profit and deduplicates selected sale',
    () {
      final buys = [trade('a', 1, '매수', 100, 10), trade('b', 2, '매수', 200, 10)];
      final sells = [
        trade('c', 3, '매도', 180, 10),
        trade('d', 4, '매도', 180, 10),
      ];
      final chart = JournalChartScreen(
        buy: sells.last,
        relatedBuys: buys,
        relatedSells: sells,
        linkedSells: sells,
        firestoreService: _NoBackend(),
      );
      expect(chart.ledger!.events, hasLength(4));
      expect(chart.ledger!.realized, 600);
      expect(chart.ledger!.effectFor('c')!.realized, 300);
      expect(chart.ledger!.effectFor('d')!.beforeAverage, 150);
    },
  );
  test('chart exposes no trusted trade effect for ambiguous history', () {
    final buy = trade('a', 1, '매수', 100, 10);
    final sell = trade('b', 1, '매도', 180, 10);
    final chart = JournalChartScreen(
      buy: buy,
      relatedSells: [sell],
      firestoreService: _NoBackend(),
    );
    expect(chart.ledger!.reliable, isFalse);
    expect(chart.ledger!.effectFor(sell.id), isNull);
  });
  testWidgets(
    'actual day cards hide fabricated profit for same-time buy and sale',
    (tester) async {
      final buy = trade('a', 1, '매수', 100, 10, market: 'KR');
      final sell = trade('b', 1, '매도', 180, 10, market: 'KR');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JournalDateSection(
                timeline: [sell, buy],
                buysByStock: {
                  'KR:TEST': [buy],
                },
                sellsByStock: {
                  'KR:TEST': [sell],
                },
                firestoreService: _NoBackend(),
                onEdit: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('거래 순서·수량 확인 필요'), findsNWidgets(2));
      expect(find.text('확인 필요'), findsOneWidget);
      expect(find.textContaining('+₩800'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
