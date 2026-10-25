import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

Future<String> savePostImage(String url, {http.Client? httpClient}) async {
  final client = httpClient ?? http.Client();
  try {
    final response = await client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw StateError('이미지를 불러오지 못했습니다.');
    }
    final mime =
        response.headers['content-type']?.split(';').first ?? 'image/jpeg';
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final name = 'stockstorage_${DateTime.now().millisecondsSinceEpoch}';
    final file = XFile.fromData(
      response.bodyBytes,
      mimeType: mime,
      name: '$name.$ext',
    );
    String message;
    if (kIsWeb) {
      await file.saveTo('$name.$ext');
      message = '이미지 다운로드를 시작했습니다.';
    } else if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw StateError('사진 저장 권한을 허용해 주세요.');
      }
      await Gal.putImageBytes(response.bodyBytes, name: name);
      message = '사진첩에 저장했습니다.';
    } else {
      await Share.shareXFiles([file]);
      message = '이미지 내보내기를 열었습니다.';
    }
    return message;
  } finally {
    if (httpClient == null) client.close();
  }
}
