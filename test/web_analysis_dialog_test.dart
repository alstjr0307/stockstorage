import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/web/web_analysis_dialog.dart';

void main() {
  testWidgets('web confirms analysis without an ad or a subscription action', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const WebAnalysisDialog(used: 1, limit: 3),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘 남은 횟수 2 / 3회'), findsOneWidget);
    expect(find.text('광고 보기'), findsNothing);
    expect(find.text('프리미엄 보기'), findsNothing);
    await tester.tap(find.text('분석 시작'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('exhausted quota cannot start analysis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebAnalysisDialog(used: 3, limit: 3)),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '분석 시작'))
          .onPressed,
      isNull,
    );
  });
}
