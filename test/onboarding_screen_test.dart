import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockstorage/screens/onboarding_screen.dart';
import 'package:stockstorage/services/stock_price_service.dart';

const stock = StockSearchResult(
  ticker: '005930',
  name: '삼성전자',
  market: 'KS',
  exchange: 'KOSPI',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first visit searches immediately and preserves selected stock', (
    tester,
  ) async {
    final selected = <StockSearchResult?>[];
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onComplete: selected.add,
          searchStocks: (_) async => [stock],
          recordEvent: (name, parameters) async => events.add(name),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(await shouldShowOnboarding(), isTrue);
    await tester.enterText(find.byType(TextField), '삼성전자');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삼성전자').last);
    await tester.pumpAndSettle();
    expect(selected, [stock]);
    expect(await shouldShowOnboarding(), isFalse);
    expect(events, ['onboarding_view', 'onboarding_complete']);
  });

  testWidgets(
    'browse bypasses login even when analytics fails; completes once',
    (tester) async {
      final selected = <StockSearchResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onComplete: selected.add,
            searchStocks: (_) async => [],
            recordEvent: (_, _) async => throw StateError('offline'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('먼저 홈 둘러보기'));
      await tester.tap(find.text('먼저 홈 둘러보기'));
      await tester.pumpAndSettle();
      expect(selected, [null]);
      expect(await shouldShowOnboarding(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('previous onboarding completion stays respected', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed_v1': true});
    expect(await shouldShowOnboarding(), isFalse);
  });

  testWidgets(
    'small screen with large text keeps search and browse accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: OnboardingScreen(
            onComplete: (_) {},
            searchStocks: (_) async => [],
            recordEvent: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(find.text('먼저 홈 둘러보기').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
