import 'package:flutter/widgets.dart';

// 웹에서 image_picker 의 XFile.path 는 blob URL 이라 Image.network 로 표시된다.
Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) =>
    Image.network(path, width: width, height: height, fit: fit);
