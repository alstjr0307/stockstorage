import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockstorage/services/post_image_save_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var access = true;
  setUp(() {
    calls.clear();
    access = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gal'), (call) async {
          calls.add(call);
          if (call.method == 'hasAccess' || call.method == 'requestAccess') {
            return access;
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gal'), null);
  });
  test('downloads image bytes and saves to the gallery', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    expect(
      await savePostImage('https://example.com/photo', httpClient: client),
      '사진첩에 저장했습니다.',
    );
    final save = calls.singleWhere((call) => call.method == 'putImageBytes');
    expect(save.arguments['bytes'], [1, 2, 3]);
    expect(save.arguments['album'], isNull);
  });
  test('failed downloads never write to the gallery', () async {
    final client = MockClient((_) async => http.Response('missing', 404));
    await expectLater(
      savePostImage('https://example.com/photo', httpClient: client),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });
  test('denied permission does not report successful saving', () async {
    access = false;
    final client = MockClient((_) async => http.Response.bytes([1], 200));
    await expectLater(
      savePostImage('https://example.com/photo', httpClient: client),
      throwsStateError,
    );
    expect(calls.map((call) => call.method), ['hasAccess', 'requestAccess']);
  });
}
