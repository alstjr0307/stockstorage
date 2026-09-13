import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockstorage/screens/stock_search_screen.dart';
import 'package:stockstorage/services/stock_price_service.dart';
import 'package:stockstorage/widgets/stock_search_field.dart';

const _oldResult = StockSearchResult(
  ticker: 'OLD',
  name: 'Old company',
  market: 'US',
  exchange: 'NASDAQ',
);
const _newResult = StockSearchResult(
  ticker: 'NEW',
  name: 'New company',
  market: 'US',
  exchange: 'NASDAQ',
);

class _SearchRequests {
  final queries = <String>[];
  final pending = <Completer<List<StockSearchResult>>>[];

  Future<List<StockSearchResult>> search(String query) {
    queries.add(query);
    final request = Completer<List<StockSearchResult>>();
    pending.add(request);
    return request.future;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _SearchRequests requests, {
  required bool fullScreen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: fullScreen
          ? StockSearchScreen(searchStocks: requests.search, onPick: (_) {})
          : Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: StockSearchField(
                  initialTicker: '',
                  initialName: '',
                  onSelected: (_, _, _) {},
                  searchStocks: requests.search,
                ),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final fullScreen in [true, false]) {
    final label = fullScreen ? 'search screen' : 'search field';

    testWidgets('$label ignores older responses arriving last', (tester) async {
      final requests = _SearchRequests();
      await _mount(tester, requests, fullScreen: fullScreen);
      await _type(tester, 'old');
      await _type(tester, 'new');

      requests.pending[1].complete([_newResult]);
      await tester.pumpAndSettle();
      requests.pending[0].complete([_oldResult]);
      await tester.pumpAndSettle();

      expect(find.text('New company'), findsOneWidget);
      expect(find.text('Old company'), findsNothing);
    });

    testWidgets('$label ignores an old response for a retyped query', (
      tester,
    ) async {
      final requests = _SearchRequests();
      await _mount(tester, requests, fullScreen: fullScreen);
      await _type(tester, 'same');
      await _type(tester, '');
      await _type(tester, 'same');

      requests.pending[1].complete([_newResult]);
      await tester.pumpAndSettle();
      requests.pending[0].complete([_oldResult]);
      await tester.pumpAndSettle();

      expect(find.text('New company'), findsOneWidget);
      expect(find.text('Old company'), findsNothing);
    });

    testWidgets('$label clears loading and rejects results after clearing', (
      tester,
    ) async {
      final requests = _SearchRequests();
      await _mount(tester, requests, fullScreen: fullScreen);
      await _type(tester, 'old');
      if (fullScreen) {
        await tester.tap(find.byTooltip('검색어 지우기'));
      } else {
        await tester.enterText(find.byType(TextField), '');
      }
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      requests.pending.single.complete([_oldResult]);
      await tester.pumpAndSettle();
      expect(find.text('Old company'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('$label removes old choices as soon as input changes', (
      tester,
    ) async {
      final requests = _SearchRequests();
      await _mount(tester, requests, fullScreen: fullScreen);
      await _type(tester, 'old');
      requests.pending.single.complete([_oldResult]);
      await tester.pumpAndSettle();
      expect(find.text('Old company'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump();
      expect(find.text('Old company'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 450));
      requests.pending.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Old company'), findsNothing);
    });

    testWidgets('$label safely ignores results after disposal', (tester) async {
      final requests = _SearchRequests();
      await _mount(tester, requests, fullScreen: fullScreen);
      await _type(tester, 'old');
      await tester.pumpWidget(const SizedBox.shrink());
      requests.pending.single.complete([_oldResult]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search screen waits for results before showing an empty state', (
    tester,
  ) async {
    final requests = _SearchRequests();
    await _mount(tester, requests, fullScreen: true);
    await tester.enterText(find.byType(TextField), 'unknown');
    await tester.pump();
    expect(find.textContaining('검색 결과가 없어요'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(requests.queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 280));
    requests.pending.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('"unknown" 검색 결과가 없어요'), findsOneWidget);
  });

  testWidgets('submitting cancels the scheduled duplicate search', (
    tester,
  ) async {
    final requests = _SearchRequests();
    await _mount(tester, requests, fullScreen: true);
    await tester.enterText(find.byType(TextField), 'AAPL');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 450));
    expect(requests.queries, ['AAPL']);
    requests.pending.single.complete([_newResult]);
    await tester.pumpAndSettle();
  });

  testWidgets('a recent search cancels pending typed input', (tester) async {
    SharedPreferences.setMockInitialValues({
      'stock_search_recent_v1': ['AAPL'],
    });
    final requests = _SearchRequests();
    await _mount(tester, requests, fullScreen: true);
    await tester.enterText(find.byType(TextField), 'old');
    // The recent chip is still mounted until the next frame.
    await tester.tap(find.text('AAPL'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(requests.queries, ['AAPL']);
    requests.pending.single.complete([_newResult]);
    await tester.pumpAndSettle();
    expect(find.text('New company'), findsOneWidget);
  });
}
