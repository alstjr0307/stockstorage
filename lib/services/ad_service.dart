import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const bool _useTestAds = false;
const bool _adsEnabled = true;

class AdService {
  AdService._();
  static final instance = AdService._();

  // ── 광고 단위 ID ────────────────────────────────────────────────────────
  static String get _bannerAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/8465933202';
    return 'ca-app-pub-6925657557995580/6772176184';
  }

  static String get _interstitialAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/5598098844';
    return 'ca-app-pub-6925657557995580/5025289757';
  }

  // ── 배너 광고 ─────────────────────────────────────────────────────────
  static bool get adsEnabled => _adsEnabled;
  static String get bannerAdUnitId => _bannerAdUnitId;

  // ── 전면 광고 ─────────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  void loadInterstitial() {
    if (kIsWeb || !_adsEnabled) return;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
              loadInterstitial(); // 다음 광고 미리 로드
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialReady = false;
        },
      ),
    );
  }

  void showInterstitialIfReady() {
    if (!_adsEnabled) return;
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

}
