import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/widgets/keep_alive_section.dart';

void main() {
  for (final loadedHeight in [0.0, 320.0]) {
    testWidgets('retains async section of height $loadedHeight on round trip', (
      tester,
    ) async {
      final controller = ScrollController();
      final result = Completer<double>();
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              cacheExtent: 0,
              children: [
                const SizedBox(height: 200),
                KeepAliveSection(
                  child: _AsyncSection(
                    load: () {
                      loads++;
                      return result.future;
                    },
                  ),
                ),
                const SizedBox(height: 3000),
              ],
            ),
          ),
        ),
      );
      result.complete(loadedHeight);
      await tester.pump();
      final extent = controller.position.maxScrollExtent;
      final state = tester.state(find.byType(_AsyncSection));
      for (var i = 0; i < 3; i++) {
        controller.jumpTo(2000);
        await tester.pumpAndSettle();
        controller.jumpTo(0);
        await tester.pump();
        expect(tester.state(find.byType(_AsyncSection)), same(state));
        expect(loads, 1);
        expect(controller.position.maxScrollExtent, extent);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}

class _AsyncSection extends StatefulWidget {
  const _AsyncSection({required this.load});
  final Future<double> Function() load;

  @override
  State<_AsyncSection> createState() => _AsyncSectionState();
}

class _AsyncSectionState extends State<_AsyncSection> {
  late final Future<double> result = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<double>(
    future: result,
    builder: (_, snapshot) => SizedBox(height: snapshot.data ?? 180),
  );
}
