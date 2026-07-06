// 로컬(픽커로 고른) 이미지를 플랫폼 안전하게 표시.
// 네이티브: Image.file(File(path)) / 웹: Image.network(blob url)
import 'package:flutter/widgets.dart';

import 'local_image_web.dart'
    if (dart.library.io) 'local_image_io.dart' as impl;

Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) =>
    impl.localImage(path, width: width, height: height, fit: fit);
