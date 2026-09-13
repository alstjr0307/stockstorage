import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/ad_service.dart';
import 'package:stockstorage/widgets/banner_ad_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AdService.readinessListenable.value = false;
    AdService.setPremium(false);
    AdService.setAdmin(false);
  });

  tearDown(() {
    AdService.readinessListenable.value = false;
    AdService.setPremium(false);
  });

  test('all ad entry points are blocked while startup is pending', () async {
    expect(AdService.adsEnabled, isFalse);
    AdService.instance.loadInterstitial();
    AdService.instance.showInterstitialIfReady();
    AdService.instance.showIndicatorDetailInterstitialIfReady();
    AdService.instance.showAiAnalysisDetailInterstitialIfReady();
    expect(
      await AdService.instance.showAiAnalysisRewardedAd(),
      RewardedAdResult.failedToLoad,
    );
    // Any platform request here would fail with MissingPluginException.
  });

  testWidgets('banner stays hidden and does not prewarm before readiness', (
    tester,
  ) async {
    BannerAdWidget.prewarm(slotId: 'pending-prewarm');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BannerAdWidget(slotId: 'pending-banner', useCache: false),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BannerAdWidget)).height, 0);
  });

  testWidgets('a mounted banner loads when startup becomes ready', (
    tester,
  ) async {
    final calls = <String>[];
    const channel = 'plugins.flutter.io/google_mobile_ads';
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(channel, (
      message,
    ) async {
      // The plugin uses a custom argument codec; only inspect the standard
      // method name because this test checks request timing, not the payload.
      calls.add(
        const StandardMessageCodec().readValue(ReadBuffer(message!)) as String,
      );
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BannerAdWidget(slotId: 'ready-banner', useCache: false),
        ),
      ),
    );
    expect(calls, isEmpty);
    AdService.markInitialized();
    await tester.pump();
    expect(calls.where((call) => call == 'loadBannerAd'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('premium users remain ad-free after initialization', (
    tester,
  ) async {
    AdService.setPremium(true);
    AdService.markInitialized();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BannerAdWidget(slotId: 'premium-banner', useCache: false),
        ),
      ),
    );
    AdService.instance.loadInterstitial();
    expect(
      await AdService.instance.showAiAnalysisRewardedAd(),
      RewardedAdResult.failedToLoad,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BannerAdWidget)).height, 0);
  });
}
