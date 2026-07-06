import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

Future<XFile> pngToShareFile(Uint8List bytes, String name) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  return XFile(file.path);
}
