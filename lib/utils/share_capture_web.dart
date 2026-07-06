import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

Future<XFile> pngToShareFile(Uint8List bytes, String name) async =>
    XFile.fromData(bytes, mimeType: 'image/png', name: name);
