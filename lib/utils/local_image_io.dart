import 'dart:io';

import 'package:flutter/widgets.dart';

Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) =>
    Image.file(File(path), width: width, height: height, fit: fit);
