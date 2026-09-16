@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/utils/paste_image.dart';
import 'package:web/web.dart' as web;

web.ClipboardEvent pasteHtml(String html) {
  final data = web.DataTransfer();
  data.setData('text/html', html);
  final event = web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(clipboardData: data, cancelable: true),
  );
  web.document.dispatchEvent(event);
  return event;
}

void main() {
  test('image HTML preserves text/image order and cancels native paste', () {
    List<PastedPart>? result;
    final cancel = listenPastedContent((parts) => result = parts);
    addTearDown(cancel);
    final event = pasteHtml(
      '<p>before</p><img src="https://example.com/chart.png"><p>after</p>',
    );
    expect(event.defaultPrevented, isTrue);
    expect(result!.map((p) => p.text ?? p.imageUrl), [
      'before',
      'https://example.com/chart.png',
      'after',
    ]);
  });

  test('inactive editor and plain text retain browser paste behavior', () {
    var calls = 0;
    var active = false;
    final cancel = listenPastedContent(
      (_) => calls++,
      shouldHandle: () => active,
    );
    addTearDown(cancel);
    expect(
      pasteHtml('<img src="https://example.com/a.png">').defaultPrevented,
      isFalse,
    );
    active = true;
    expect(pasteHtml('<p>text only</p>').defaultPrevented, isFalse);
    expect(calls, 0);
  });

  test('disposed listener no longer consumes images', () {
    var calls = 0;
    final cancel = listenPastedContent((_) => calls++);
    cancel();
    expect(
      pasteHtml('<img src="https://example.com/a.png">').defaultPrevented,
      isFalse,
    );
    expect(calls, 0);
  });
}
