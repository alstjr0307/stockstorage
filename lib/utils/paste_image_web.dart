import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

/// document 의 paste 이벤트에서 이미지 파일을 뽑아 blob URL 기반 [XFile] 로 전달한다.
/// image_picker_for_web 과 동일한 형태라 미리보기(Image.network)와 업로드가 그대로 동작한다.
void Function() listenPastedImages(void Function(List<XFile>) onImages) {
  void handle(web.Event event) {
    final clipboard = (event as web.ClipboardEvent).clipboardData;
    if (clipboard == null) return;

    final files = clipboard.files;
    final picked = <XFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      picked.add(
        XFile(
          web.URL.createObjectURL(file),
          mimeType: file.type,
          name: file.name.isEmpty ? _fallbackName(file.type) : file.name,
        ),
      );
    }
    if (picked.isEmpty) return;

    // 이미지가 있을 때만 기본 붙여넣기(파일명 텍스트 삽입 등)를 막는다.
    event.preventDefault();
    onImages(picked);
  }

  final listener = handle.toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

String _fallbackName(String mimeType) {
  final ext = switch (mimeType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };
  return 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';
}
