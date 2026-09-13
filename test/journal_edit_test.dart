import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/models/trading_journal.dart';
import 'package:stockstorage/screens/trading_journal_screen.dart';
import 'package:stockstorage/services/firestore_service.dart';
import 'package:stockstorage/services/journal_ledger.dart';
import 'package:stockstorage/services/journal_v2_repository.dart';
import 'journal_v2_test.dart' show trade;

class _Backend implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backend access');
}

class _Repository implements JournalV2Repository {
  final pending = Completer<void>();
  TradingJournal? saved;
  TradingJournal? source;
  int calls = 0;
  @override
  Future<void> save(TradingJournal next, {TradingJournal? original}) {
    calls++;
    saved = next;
    source = original;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository access');
}

void main() {
  test('editing past price recomputes realized profit and remaining cost', () {
    final old = trade('a', 1, '매수', 100, 10);
    final next = trade('a', 1, '매수', 120, 10);
    final later = [trade('b', 2, '매수', 200, 10), trade('s', 3, '매도', 180, 5)];
    expect(JournalLedger.validateMutation([old, ...later], next: next), isNull);
    final p = JournalLedger.project([next, ...later]).single;
    expect(p.realized, 100);
    expect(p.average, 160);
    expect(p.cost, 2400);
    expect(p.effectFor('a')!.trade.price, 120);
    expect(old.price, 100);
  });

  test('date and quantity edits cannot borrow from future buys', () {
    final all = [trade('a', 1, '매수', 100, 10), trade('s', 3, '매도', 180, 10)];
    for (final next in [
      trade('a', 4, '매수', 100, 10),
      trade('a', 1, '매수', 100, 9),
      trade('s', 0, '매도', 180, 10),
      trade('s', 3, '매도', 180, 11),
    ]) {
      expect(JournalLedger.validateMutation(all, next: next), isNotNull);
    }
    expect(
      JournalLedger.validateMutation(all, next: trade('a', 2, '매수', 100, 10)),
      isNull,
    );
  });

  test('exact edit retry is accepted but conflicting values are not', () {
    final old = trade('a', 1, '매수', 100, 10);
    final next = trade('a', 2, '매수', 120, 10, note: '수정');
    expect(JournalV2Repository.editAlreadyApplied(next, old, next), isTrue);
    expect(JournalV2Repository.editAlreadyApplied(old, old, next), isFalse);
    expect(JournalV2Repository.editAlreadyApplied(null, old, next), isFalse);
    expect(
      JournalV2Repository.editAlreadyApplied(
        trade('a', 2, '매수', 130, 10),
        old,
        next,
      ),
      isFalse,
    );
    expect(JournalV2Repository.editAlreadyApplied(next, next, next), isFalse);
  });

  testWidgets(
    'edit captures inputs once, preserves metadata, and survives dismissal during save',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = trade('a', 1, '매수', 100, 10, market: 'KR');
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalFormSheet(
              uid: old.uid,
              nickname: 'new nickname',
              existing: old,
              firestoreService: _Backend(),
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-price')),
        '120',
      );
      await tester.enterText(
        find.byKey(const ValueKey('journal-note')),
        '수정 메모',
      );
      await tester.ensureVisible(find.text('수정 완료'));
      await tester.tap(find.text('수정 완료'));
      await tester.pump();
      expect(repository.calls, 1);
      expect(repository.saved!.price, 120);
      expect(repository.saved!.note, '수정 메모');
      expect(repository.saved!.id, old.id);
      expect(repository.saved!.createdAt, old.createdAt);
      expect(repository.saved!.linkedBuyId, old.linkedBuyId);
      expect(repository.saved!.likes, old.likes);
      expect(repository.saved!.nickname, old.nickname);
      expect(repository.source, same(old));
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((w) => w.absorbing),
        isTrue,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      repository.pending.completeError(const JournalWriteException('충돌'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date menu opens same stock buy/sell; closed buy remains editable',
    (tester) async {
      final buy = trade('a', 1, '매수', 100, 10, market: 'KR');
      final extra = trade('b', 2, '매수', 150, 10, market: 'KR');
      String? selected;
      TradingJournal? selectedStock;
      Widget app(List<TradingJournal> buys, List<TradingJournal> sells) =>
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: JournalDateSection(
                  key: ValueKey(sells.length),
                  timeline: buys.reversed.toList(),
                  buysByStock: {'KR:TEST': buys},
                  sellsByStock: {'KR:TEST': sells},
                  firestoreService: _Backend(),
                  onEdit: (j) => selectedStock = j,
                  onAddTrade: (j, action) {
                    selectedStock = j;
                    selected = action;
                  },
                ),
              ),
            ),
          );
      await tester.pumpWidget(app([buy, extra], []));
      await tester.pumpAndSettle();
      expect(find.text('추가매수'), findsOneWidget);
      for (final action in ['매수', '매도']) {
        await tester.tap(find.byTooltip('거래 메뉴'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action == '매수' ? '추가매수' : '매도').last);
        await tester.pumpAndSettle();
        expect(selected, action);
        expect(selectedStock!.id, extra.id);
      }
      await tester.pumpWidget(
        app([buy], [trade('s', 3, '매도', 120, 10, market: 'KR')]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('거래 메뉴'));
      await tester.pumpAndSettle();
      expect(find.text('매도 · 보유수량 없음'), findsOneWidget);
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('매도 · 보유수량 없음'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, isFalse);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(selectedStock!.id, buy.id);
      expect(tester.takeException(), isNull);
    },
  );
}
