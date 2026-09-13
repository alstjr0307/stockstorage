import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/screens/trading_journal_screen.dart';
import 'package:stockstorage/services/firestore_service.dart';
import 'journal_v2_test.dart' show trade;

class _NoNetworkFirestore implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backend access');
}

void main() {
  testWidgets(
    'original day view selects empty date and navigates adjacent trades',
    (tester) async {
      for (final entry in {
        'Pretendard': 'assets/fonts/Pretendard-Regular.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          entry.key,
        )..addFont(rootBundle.load(entry.value))).load();
      }
      tester.view.physicalSize = const Size(390, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final buys = [
        trade('a', 1, '매수', 72000, 10, ticker: '삼성전자', market: 'KR'),
        trade('b', 3, '매수', 66000, 10, ticker: '삼성전자', market: 'KR'),
      ];
      Widget app(bool dark) => MaterialApp(
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'Pretendard',
          brightness: dark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: dark
              ? const Color(0xFF0A0E1A)
              : const Color(0xFFF0F4F8),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10B981),
            brightness: dark ? Brightness.dark : Brightness.light,
            surface: dark ? const Color(0xFF1A2035) : Colors.white,
          ),
        ),
        home: Scaffold(
          body: ListView(
            children: [
              JournalDateSection(
                timeline: buys.reversed.toList(),
                buysByStock: {'KR:삼성전자': buys},
                sellsByStock: const {},
                firestoreService: _NoNetworkFirestore(),
                onEdit: (_) {},
              ),
            ],
          ),
        ),
      );
      for (final dark in [true, false]) {
        await tester.pumpWidget(app(dark));
        await tester.pumpAndSettle();
        expect(find.text('2026.01.03'), findsOneWidget);
        expect(find.text('추가매수'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../output/journal-design/original-${dark ? 'dark' : 'light'}.png',
          ),
        );
      }
      await tester.tap(find.text('2026.01.03'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('2').last);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('2026.01.02'), findsOneWidget);
      expect(find.text('이 날짜에는 매매 기록이 없습니다'), findsOneWidget);
      await tester.tap(find.byTooltip('이전 거래일'));
      await tester.pumpAndSettle();
      expect(find.text('2026.01.01'), findsOneWidget);
      await tester.tap(find.byTooltip('다음 거래일'));
      await tester.pumpAndSettle();
      expect(find.text('2026.01.03'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
