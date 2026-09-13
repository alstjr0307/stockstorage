import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/boot/native_boot_io.dart' as native;
import 'package:stockstorage/services/ad_service.dart';

void main() {
  testWidgets(
    'SDK failure retries, stays blocked, and allows a later attempt',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
      var attempts = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
      if (call.method != 'MobileAds#initialize') return null;
        attempts++;
        throw PlatformException(code: 'temporarily-unavailable');
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        AdService.readinessListenable.value = false;
      });

      final first = native.initAds();
      expect(identical(first, native.initAds()), isTrue);
      await tester.pump();
      expect(attempts, 1);
      expect(AdService.adsEnabled, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(attempts, 2);
      await tester.pump(const Duration(seconds: 4));
      await first;
      expect(attempts, 3);
      expect(AdService.adsEnabled, isFalse);

      final retry = native.initAds();
      expect(identical(first, retry), isFalse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      await retry;
      expect(attempts, 6);
      expect(AdService.adsEnabled, isFalse);
    },
  );
}
