// 캡처한 PNG 바이트를 Share.shareXFiles 에 넘길 XFile 로 변환.
// 네이티브: temp 파일에 써서 경로 기반 XFile / 웹: 메모리 기반 XFile.fromData
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'share_capture_web.dart'
    if (dart.library.io) 'share_capture_io.dart' as impl;

Future<XFile> pngToShareFile(Uint8List bytes, String name) =>
    impl.pngToShareFile(bytes, name);
