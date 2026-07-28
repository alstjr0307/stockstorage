import 'dart:convert';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import 'paste_image.dart';

const _blockTags = {
  'ADDRESS', 'ARTICLE', 'BLOCKQUOTE', 'DIV', 'FIGCAPTION', 'FIGURE', 'FOOTER',
  'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEADER', 'LI', 'P', 'PRE', 'SECTION',
  'TR', 'UL', 'OL', 'TABLE',
};

/// document 의 paste 이벤트에서 사진과 글을 순서대로 뽑아 전달한다.
/// - 사진 파일(스크린샷 등) → 새로 올릴 사진
/// - 사진이 들어간 글(HTML) → 글과 사진을 원래 순서대로
/// - 글만 있을 때는 가로채지 않고 Flutter 기본 붙여넣기에 맡긴다.
void Function() listenPastedContent(void Function(List<PastedPart>) onPasted) {
  void handle(web.Event event) {
    final clipboard = (event as web.ClipboardEvent).clipboardData;
    if (clipboard == null) return;

    final files = _imageFiles(clipboard);
    if (files.isNotEmpty) {
      event.preventDefault();
      onPasted(files.map(PastedPart.file).toList());
      return;
    }

    final html = clipboard.getData('text/html');
    if (html.isEmpty || !html.toLowerCase().contains('<img')) return;

    List<PastedPart> parts;
    try {
      parts = _partsFromHtml(html);
    } catch (_) {
      return; // 파싱이 막히면 기본 텍스트 붙여넣기에 맡긴다.
    }
    if (!parts.any((part) => part.isImage)) return;

    event.preventDefault();
    onPasted(parts);
  }

  final listener = handle.toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

List<XFile> _imageFiles(web.DataTransfer clipboard) {
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
  return picked;
}

/// 복사한 HTML에서 글과 사진만 순서대로 남긴다(스크립트·스타일·서식은 버림).
List<PastedPart> _partsFromHtml(String html) {
  final document = web.DOMParser().parseFromString(html.toJS, 'text/html');
  final parts = <PastedPart>[];
  final buffer = StringBuffer();

  void flushText() {
    final text = buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    buffer.clear();
    if (text.isNotEmpty) parts.add(PastedPart.text(text));
  }

  void walk(web.Node node) {
    if (node.nodeType == web.Node.TEXT_NODE) {
      final text = (node.textContent ?? '').replaceAll(RegExp(r'\s+'), ' ');
      if (text.trim().isNotEmpty) buffer.write(text);
      return;
    }
    if (node.nodeType != web.Node.ELEMENT_NODE) return;

    final element = node as web.Element;
    final tag = element.tagName.toUpperCase();
    if (tag == 'SCRIPT' || tag == 'STYLE' || tag == 'NOSCRIPT') return;
    if (tag == 'BR') {
      buffer.write('\n');
      return;
    }
    if (tag == 'IMG') {
      final image = _imagePart(element.getAttribute('src') ?? '');
      if (image == null) return;
      flushText();
      parts.add(image);
      return;
    }

    final children = element.childNodes;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i);
      if (child != null) walk(child);
    }
    if (_blockTags.contains(tag)) buffer.write('\n');
  }

  final body = document.body;
  if (body != null) {
    final children = body.childNodes;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i);
      if (child != null) walk(child);
    }
  }
  flushText();
  return parts;
}

PastedPart? _imagePart(String src) {
  final url = src.trim();
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return PastedPart.imageUrl(url);
  }
  if (!url.startsWith('data:image/')) return null;

  // data: URL 로 들어온 사진은 파일로 바꿔 우리 저장소에 올린다.
  final comma = url.indexOf(',');
  if (comma == -1 || !url.substring(0, comma).contains(';base64')) return null;
  final mime = url.substring(5, url.indexOf(';'));
  try {
    final bytes = base64Decode(url.substring(comma + 1));
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mime),
    );
    return PastedPart.file(
      XFile(
        web.URL.createObjectURL(blob),
        mimeType: mime,
        name: _fallbackName(mime),
      ),
    );
  } catch (_) {
    return null;
  }
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
