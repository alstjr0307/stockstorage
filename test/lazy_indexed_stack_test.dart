import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/widgets/lazy_indexed_stack.dart';

class _Page extends StatefulWidget {
  const _Page({required this.index, required this.onInit, this.label = ''});

  final int index;
  final ValueChanged<int> onInit;
  final String label;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.onInit(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('${widget.index}:$taps:${widget.label}'),
    );
  }
}

void main() {
  testWidgets('only the selected page initializes on launch', (tester) async {
    final initialized = <int>[];
    final built = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LazyIndexedStack(
          index: 0,
          itemCount: 8,
          itemBuilder: (_, index) {
            built.add(index);
            return _Page(index: index, onInit: initialized.add);
          },
        ),
      ),
    );
    expect(initialized, [0]);
    expect(built, [0]);
  });

  testWidgets('first visits initialize pages and returning keeps their state', (
    tester,
  ) async {
    final initialized = <int>[];
    Future<void> show(int index) => tester.pumpWidget(
      MaterialApp(
        home: LazyIndexedStack(
          index: index,
          itemCount: 4,
          itemBuilder: (_, i) => _Page(index: i, onInit: initialized.add),
        ),
      ),
    );

    await show(0);
    await tester.tap(find.text('0:0:'));
    await tester.pump();
    await show(2);
    expect(initialized, [0, 2]);
    await show(0);
    expect(find.text('0:1:'), findsOneWidget);
    expect(initialized, [0, 2]);
    expect(find.text('2:0:'), findsNothing);
  });

  testWidgets('visited pages still receive updated inputs', (tester) async {
    final initialized = <int>[];
    Future<void> show(String label) => tester.pumpWidget(
      MaterialApp(
        home: LazyIndexedStack(
          index: 0,
          itemCount: 2,
          itemBuilder: (_, i) =>
              _Page(index: i, onInit: initialized.add, label: label),
        ),
      ),
    );
    await show('guest');
    await tester.tap(find.text('0:0:guest'));
    await tester.pump();
    await show('member');
    expect(find.text('0:1:member'), findsOneWidget);
    expect(initialized, [0]);
  });

  testWidgets('removing an admin tab forgets it until it is visited again', (
    tester,
  ) async {
    final initialized = <int>[];
    Future<void> show(int index, int count) => tester.pumpWidget(
      MaterialApp(
        home: LazyIndexedStack(
          index: index,
          itemCount: count,
          itemBuilder: (_, i) => _Page(index: i, onInit: initialized.add),
        ),
      ),
    );
    await show(2, 3);
    await show(0, 2);
    await show(0, 3);
    expect(initialized, [2, 0]);
    await show(2, 3);
    expect(initialized, [2, 0, 2]);
  });

  testWidgets('animations are disabled in visited but hidden tabs', (
    tester,
  ) async {
    final initialized = <int>[];
    Future<void> show(int index) => tester.pumpWidget(
      MaterialApp(
        home: LazyIndexedStack(
          index: index,
          itemCount: 2,
          itemBuilder: (_, i) => _Page(index: i, onInit: initialized.add),
        ),
      ),
    );
    await show(0);
    await show(1);
    final pages = tester.elementList(find.byType(_Page, skipOffstage: false));
    for (final page in pages) {
      final index = (page.widget as _Page).index;
        expect(TickerMode.valuesOf(page).enabled, index == 1);
    }
  });
}
