// 웹에서 Ctrl+V(⌘V)로 붙여넣은 내용을 글·사진 순서대로 받아오는 헬퍼.
// 네이티브에서는 아무 것도 하지 않는다.
import 'package:cross_file/cross_file.dart';

import 'paste_image_web.dart'
    if (dart.library.io) 'paste_image_io.dart'
    as impl;

/// 붙여넣은 조각 하나. 글이거나, 새로 올릴 사진이거나, 이미 URL이 있는 사진.
class PastedPart {
  const PastedPart.text(String this.text) : file = null, imageUrl = null;
  const PastedPart.file(XFile this.file) : text = null, imageUrl = null;
  const PastedPart.imageUrl(String this.imageUrl) : text = null, file = null;

  final String? text;
  final XFile? file;
  final String? imageUrl;

  bool get isText => text != null;
  bool get isImage => !isText;
}

/// 클립보드 붙여넣기 구독. 해제하려면 반환된 함수를 호출한다.
void Function() listenPastedContent(void Function(List<PastedPart>) onPasted) =>
    impl.listenPastedContent(onPasted);
