import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/widgets/analysis_follow_card.dart';

void main() {
  testWidgets('does not save twice while waiting, then shows saved state', (
    tester,
  ) async {
    final state = StreamController<bool>();
    addTearDown(state.close);
    final save = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisFollowCard(
            savedStream: state.stream,
            onSave: () {
              calls++;
              return save.future;
            },
            onAlert: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('관심종목 저장'));
    expect(calls, 0); // No write before the existing state is loaded.
    state.add(false);
    await tester.pump();
    await tester.tap(find.text('관심종목 저장'));
    await tester.pump();
    await tester.tap(find.text('관심종목 저장'));
    expect(calls, 1);
    save.complete();
    state.add(true);
    await tester.pumpAndSettle();
    expect(find.text('관심종목에 저장됨'), findsOneWidget);
  });

  testWidgets('failed save can be retried without claiming success', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisFollowCard(
            savedStream: Stream.value(false),
            onSave: () async {
              calls++;
              throw StateError('offline');
            },
            onAlert: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('관심종목 저장'));
    await tester.pumpAndSettle();
    expect(find.text('처리하지 못했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('관심종목에 저장됨'), findsNothing);
    await tester.tap(find.text('관심종목 저장'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('saved stock keeps alert action accessible on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var alerts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalysisFollowCard(
              savedStream: Stream.value(true),
              onSave: () async {},
              onAlert: () async {
                alerts++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('가격 알림 설정'));
    await tester.pumpAndSettle();
    expect(alerts, 1);
    expect(tester.takeException(), isNull);
  });
}
