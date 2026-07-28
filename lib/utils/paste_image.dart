// 웹에서 Ctrl+V(⌘V)로 붙여넣은 이미지를 XFile 로 받아오는 헬퍼.
// 네이티브에서는 아무 것도 하지 않는다.
import 'package:cross_file/cross_file.dart';

import 'paste_image_web.dart'
    if (dart.library.io) 'paste_image_io.dart'
    as impl;

/// 클립보드 이미지 붙여넣기 구독. 해제하려면 반환된 함수를 호출한다.
void Function() listenPastedImages(void Function(List<XFile>) onImages) =>
    impl.listenPastedImages(onImages);
