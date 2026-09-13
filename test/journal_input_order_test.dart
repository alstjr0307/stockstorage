import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/journal_ledger.dart';
import 'package:stockstorage/services/journal_v2_repository.dart';
import 'journal_v2_test.dart' show trade;

void main() {
  test(
    'legacy midnight dates use input order, independent of query/ID order',
    () {
      final buy = trade(
        'z',
        1,
        '매수',
        100,
        10,
        createdAt: DateTime(2026, 2, 1, 9),
      );
      final extra = trade(
        'a',
        1,
        '매수',
        200,
        10,
        createdAt: DateTime(2026, 2, 1, 10),
      );
      final sell = trade(
        's',
        1,
        '매도',
        180,
        5,
        createdAt: DateTime(2026, 2, 1, 11),
      );
      for (final rows in [
        [sell, extra, buy],
        [extra, buy, sell],
      ]) {
        final p = JournalLedger.project(rows).single;
        expect(p.reliable, isTrue);
        expect(p.events.map((e) => e.trade.id), ['z', 'a', 's']);
        expect(p.average, 150);
        expect(p.realized, 150);
        expect(p.quantity, 15);
        expect(p.effectFor('a')!.buyNumber, 2);
      }
      expect(JournalLedger.validateMutation([buy, extra], next: sell), isNull);
    },
  );

  test(
    'same day ignores hidden trade time; different days retain date order',
    () {
      final buy = trade(
        'b',
        1,
        '매수',
        100,
        10,
        tradeDate: DateTime(2026, 1, 1, 23),
        createdAt: DateTime(2026, 2, 2, 9),
      );
      final sell = trade(
        's',
        1,
        '매도',
        120,
        10,
        tradeDate: DateTime(2026, 1, 1, 1),
        createdAt: DateTime(2026, 2, 2, 10),
      );
      expect(JournalLedger.project([sell, buy]).single.realized, 200);
      expect(JournalLedger.project([sell, buy]).single.reliable, isTrue);
      final nextDaySell = trade(
        's',
        2,
        '매도',
        120,
        10,
        createdAt: DateTime(2026, 2, 1),
      );
      expect(JournalLedger.project([nextDaySell, buy]).single.reliable, isTrue);
    },
  );

  test('editing a buy preserves input order and recomputes later sale', () {
    final entered = DateTime(2026, 2, 1, 9);
    final buy = trade('b', 1, '매수', 100, 10, createdAt: entered);
    final sell = trade(
      's',
      1,
      '매도',
      120,
      5,
      createdAt: entered.add(const Duration(minutes: 1)),
    );
    final edit = trade('b', 1, '매수', 110, 10, createdAt: entered);
    expect(JournalLedger.validateMutation([buy, sell], next: edit), isNull);
    expect(JournalLedger.project([sell, edit]).single.realized, 50);
    expect(
      JournalLedger.validateMutation([
        buy,
        sell,
      ], next: trade('b', 1, '매수', 110, 4, createdAt: entered)),
      isNotNull,
    );
  });

  test(
    'genuinely unknown order and real oversells still require correction',
    () {
      final buy = trade('b', 1, '매수', 100, 10);
      final sell = trade('s', 1, '매도', 120, 10);
      expect(
        JournalLedger.project([buy, sell]).single.hasOrderAmbiguity,
        isTrue,
      );
      final firstSell = trade(
        's',
        1,
        '매도',
        120,
        10,
        createdAt: buy.createdAt.subtract(const Duration(minutes: 1)),
      );
      final p = JournalLedger.project([buy, firstSell]).single;
      expect(p.hasOrderAmbiguity, isFalse);
      expect(p.reliable, isFalse);
      expect(p.events.first.issue, '거래 당시 보유수량 초과');
    },
  );

  test(
    'only revision permission denial enables legacy compatibility',
    () async {
      expect(
        await JournalV2Repository.readCompatibleRevision(() async => 4),
        4,
      );
      expect(
        await JournalV2Repository.readCompatibleRevision(
          () async => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        isNull,
      );
      await expectLater(
        JournalV2Repository.readCompatibleRevision(
          () async => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          ),
        ),
        throwsA(isA<FirebaseException>()),
      );
    },
  );
}
