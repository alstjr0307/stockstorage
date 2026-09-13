import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockstorage/models/trading_journal.dart';
import 'package:stockstorage/services/journal_ledger.dart';
import 'package:stockstorage/services/journal_v2_repository.dart';
import 'package:stockstorage/screens/journal_v2_screen.dart';
import 'package:stockstorage/widgets/journal_experience_gate.dart';

TradingJournal trade(
  String id,
  int day,
  String action,
  double price,
  double qty, {
  String ticker = 'TEST',
  String market = 'US',
  String note = '',
  DateTime? createdAt,
  DateTime? tradeDate,
}) => TradingJournal(
  id: id,
  uid: 'test-user',
  nickname: 'test',
  stockName: ticker,
  ticker: ticker,
  market: market,
  action: action,
  price: price,
  quantity: qty,
  tradeDate: tradeDate ?? DateTime(2026, 1, day),
  note: note,
  isPublic: false,
  likes: 7,
  createdAt: createdAt ?? DateTime(2026, 2, 1),
  buyPrice: 123,
  linkedBuyId: 'legacy',
);

void main() {
  final buys = [trade('a', 1, '매수', 100, 10), trade('b', 2, '매수', 200, 10)];
  test('partial sales retain average and split sales realize total 600', () {
    final partial = JournalLedger.project([
      ...buys,
      trade('c', 3, '매도', 180, 10),
    ]).single;
    expect(partial.average, 150);
    expect(partial.cost, 1500);
    expect(partial.realized, 300);
    final closed = JournalLedger.project([
      ...buys,
      trade('c', 3, '매도', 180, 10),
      trade('d', 4, '매도', 180, 10),
    ]).single;
    expect(closed.quantity, 0);
    expect(closed.cost, 0);
    expect(closed.realized, 600);
    expect(closed.realizedRate, 20);
  });
  test('classifies down/up/same and resets after closing', () {
    final p = JournalLedger.project([
      trade('1', 1, '매수', 100, 1),
      trade('2', 2, '매수', 80, 1),
      trade('3', 3, '매수', 90, 1),
      trade('4', 4, '매수', 110, 1),
      trade('5', 5, '매도', 110, 4),
      trade('6', 6, '매수', 200, 1),
    ]).single;
    expect(p.events.map((e) => e.kind), [
      JournalBuyKind.first,
      JournalBuyKind.averageDown,
      JournalBuyKind.samePrice,
      JournalBuyKind.averageUp,
      JournalBuyKind.sell,
      JournalBuyKind.first,
    ]);
    expect(p.events.last.buyNumber, 1);
  });
  test('backdated sell cannot borrow future buys', () {
    expect(
      JournalLedger.validateMutation(buys, next: trade('c', 1, '매도', 200, 15)),
      isNotNull,
    );
  });
  test('deletion and reduced buy cannot invalidate later sale', () {
    final all = [buys.first, trade('s', 3, '매도', 120, 10)];
    expect(JournalLedger.validateMutation(all, deleteId: 'a'), isNotNull);
    expect(
      JournalLedger.validateMutation(all, next: trade('a', 1, '매수', 100, 5)),
      isNotNull,
    );
  });
  test('unrelated legacy issues do not block valid stock', () {
    expect(
      JournalLedger.validateMutation([
        trade('x', 1, '매도', 100, 10, ticker: 'BAD'),
      ], next: buys.first),
      isNull,
    );
  });
  test('memo-only edit can preserve invalid legacy finance', () {
    final old = trade('x', 1, '매도', 100, 10);
    expect(
      JournalLedger.validateMutation([
        old,
      ], next: trade('x', 1, '매도', 100, 10, note: 'updated')),
      isNull,
    );
  });
  test('same-time records are flagged; projection does not reorder source', () {
    final all = [trade('z', 1, '매수', 100, 1), trade('a', 1, '매도', 100, 1)];
    expect(JournalLedger.project(all).single.reliable, isFalse);
    expect(all.map((j) => j.id), ['z', 'a']);
  });
  test(
    'fractional quantities and native currency accounting conserve value',
    () {
      final p = JournalLedger.project([
        trade('a', 1, '매수', 100, .5),
        trade('b', 2, '매도', 130, .2),
      ]).single;
      expect(p.quantity, closeTo(.3, 1e-12));
      expect(p.average, closeTo(100, 1e-10));
      expect(
        p.realized + 140 * p.quantity - p.cost,
        closeTo(26 + 42 - 50, 1e-10),
      );
    },
  );
  test('invalid numbers and market separation', () {
    for (final price in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        JournalLedger.project([trade('a', 1, '매수', price, 1)]).single.reliable,
        isFalse,
      );
    }
    expect(
      JournalLedger.project([
        buys.first,
        trade('x', 2, '매수', 100, 1, market: 'KS'),
      ]),
      hasLength(2),
    );
  });
  test('edit payload preserves existing metadata and linkage', () {
    final payload = JournalV2Repository.editablePayload(buys.last, buys.first);
    expect(payload.keys.toSet(), {
      'price',
      'quantity',
      'tradeDate',
      'note',
      'isPublic',
    });
    for (final key in [
      'uid',
      'createdAt',
      'likes',
      'buyPrice',
      'linkedBuyId',
      'ticker',
    ]) {
      expect(payload.containsKey(key), isFalse);
    }
  });
  testWidgets('rollback choice persists and build switch overrides', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Widget app() => MaterialApp(
      home: Scaffold(
        body: JournalExperienceGate(
          modernBuilder: (_) => const Text('modern-body'),
          legacyBuilder: (_) => const Text('legacy-body'),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    if (!JournalExperienceGate.enabled) {
      expect(find.text('legacy-body'), findsOneWidget);
      expect(find.text('개선 화면으로'), findsNothing);
      return;
    }
    expect(find.text('modern-body'), findsOneWidget);
    await tester.tap(find.byTooltip('화면 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기존 화면으로'));
    await tester.pumpAndSettle();
    expect(find.text('legacy-body'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        JournalExperienceGate.preferenceKey,
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('legacy-body'), findsOneWidget);
    await tester.tap(find.byTooltip('화면 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개선 화면으로'));
    await tester.pumpAndSettle();
    expect(find.text('modern-body'), findsOneWidget);
  });
  testWidgets('preview fits narrow screen with enlarged text and USD units', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final effect = JournalLedger.project(buys).single.events.last;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: JournalTradePreview(effect: effect, reliable: true),
          ),
        ),
      ),
    );
    expect(find.text('추가매수 · 2차 매수'), findsOneWidget);
    expect(find.textContaining('\$150.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JournalTradePreview(effect: effect, reliable: false),
        ),
      ),
    );
    expect(find.text('추가매수 · 2차 매수'), findsNothing);
  });
}
