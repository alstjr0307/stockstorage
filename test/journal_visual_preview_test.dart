import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/screens/journal_v2_screen.dart';
import 'package:stockstorage/services/journal_ledger.dart';
import 'package:stockstorage/widgets/journal_visual_style.dart';
import 'journal_v2_test.dart' show trade;

void main() {
  testWidgets('render journal cards in app dark and light palette', (
    tester,
  ) async {
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final samsung = JournalLedger.project([
      trade('a', 1, '매수', 72000, 10, ticker: '삼성전자', market: 'KS'),
      trade('b', 2, '매수', 66000, 10, ticker: '삼성전자', market: 'KS'),
    ]).single;
    final nvidia = JournalLedger.project([
      trade('c', 1, '매수', 110, 5, ticker: 'NVIDIA', market: 'US'),
      trade('d', 2, '매수', 130, 5, ticker: 'NVIDIA', market: 'US'),
    ]).single;
    for (final dark in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: 'Pretendard',
            scaffoldBackgroundColor: dark
                ? const Color(0xFF0A0E1A)
                : const Color(0xFFF0F4F8),
            colorScheme: ColorScheme.fromSeed(
              seedColor: JournalVisualStyle.mint,
              brightness: dark ? Brightness.dark : Brightness.light,
              surface: dark ? const Color(0xFF1A2035) : Colors.white,
            ),
          ),
          home: JournalVisualStyle(
            child: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('preview'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              '매매일지',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(Icons.more_horiz),
                        ],
                      ),
                      const SizedBox(height: 20),
                      JournalPositionCard(
                        position: samsung,
                        price: 71000,
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      JournalPositionCard(
                        position: nvidia,
                        price: 138,
                        onTap: () {},
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '추가 매수 미리보기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      JournalTradePreview(
                        effect: samsung.events.last,
                        reliable: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../output/journal-design/${dark ? 'dark' : 'light'}.png',
        ),
      );
    }
  });
}
