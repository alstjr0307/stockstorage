import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'analytics_service.dart';

const bool _useTestAds = kDebugMode;
final bool _adsEnabled = true;

class AdService {
  AdService._();
  static final instance = AdService._();

  static bool _isAdmin = false;
  static bool get isAdmin => _isAdmin;
  static void setAdmin(bool value) => _isAdmin = value;
  bool get _shouldBlockByAdmin => _isAdmin && !_useTestAds;

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

  static String get _stockInterstitialAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/5598098844';
    return 'ca-app-pub-6925657557995580/5025289757';
  }

  static String get _indicatorInterstitialAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/7720689486';
    return 'ca-app-pub-6925657557995580/2656065066';
  }

  static String get _marketAnalysisMidBannerAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/6398470153';
    return 'ca-app-pub-6925657557995580/3939218968';
  }

  static String get _rewardedAdUnitId {
    if (kIsWeb) return '';
    if (_useTestAds) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    if (Platform.isAndroid) return 'ca-app-pub-6925657557995580/4898140479';
    return 'ca-app-pub-6925657557995580/2080405446';
  }

  // ── 배너 광고 ─────────────────────────────────────────────────────────
  static bool get adsEnabled => _adsEnabled;
  static String get bannerAdUnitId => _bannerAdUnitId;
  static String get marketAnalysisMidBannerAdUnitId =>
      _marketAnalysisMidBannerAdUnitId;

  // ── 전면 광고 ─────────────────────────────────────────────────────────
  InterstitialAd? _stockInterstitialAd;
  bool _isStockInterstitialReady = false;
  bool _isStockInterstitialLoading = false;
  InterstitialAd? _indicatorInterstitialAd;
  bool _isIndicatorInterstitialReady = false;
  bool _isIndicatorInterstitialLoading = false;
  bool _stockInterstitialConsumed = false;
  bool _pendingStockInterstitial = false;
  bool _pendingIndicatorInterstitial = false;
  int _indicatorDetailOpenCount = 0;
  static const int _interstitialEvery = 3; // 3번 중 1번만 전면광고

  void loadInterstitial() {
    _loadStockInterstitial();
    _loadIndicatorInterstitial();
  }

  void _loadStockInterstitial() {
    if (kIsWeb || !_adsEnabled) return;
    if (_isStockInterstitialLoading) return;
    if (_isStockInterstitialReady && _stockInterstitialAd != null) return;
    _isStockInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _stockInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isStockInterstitialLoading = false;
          _stockInterstitialAd?.dispose();
          _stockInterstitialAd = ad;
          _isStockInterstitialReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {
              _stockInterstitialConsumed = true;
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _stockInterstitialAd = null;
              _isStockInterstitialReady = false;
              _loadStockInterstitial(); // 다음 광고 미리 로드
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _stockInterstitialAd = null;
              _isStockInterstitialReady = false;
              _isStockInterstitialLoading = false;
              _loadStockInterstitial();
            },
          );
          if (_pendingStockInterstitial &&
              !_shouldBlockByAdmin &&
              _adsEnabled &&
              !_stockInterstitialConsumed) {
            _pendingStockInterstitial = false;
            _showLoadedStockInterstitial();
          }
        },
        onAdFailedToLoad: (error) {
          _isStockInterstitialLoading = false;
          _isStockInterstitialReady = false;
          _pendingStockInterstitial = false;
        },
      ),
    );
  }

  void cancelPendingStockInterstitial() {
    _pendingStockInterstitial = false;
  }

  void showInterstitialIfReady() {
    if (!_adsEnabled || _shouldBlockByAdmin) return;
    if (_stockInterstitialConsumed) return; // 추천주 상세 첫 노출 1회만 허용
    if (!_isStockInterstitialReady || _stockInterstitialAd == null) {
      _pendingStockInterstitial = true;
      _loadStockInterstitial();
      return;
    }
    _pendingStockInterstitial = false;
    _showLoadedStockInterstitial();
  }

  void showIndicatorDetailInterstitialIfReady() {
    if (!_adsEnabled || _shouldBlockByAdmin) return;
    _indicatorDetailOpenCount++;
    if (_indicatorDetailOpenCount == 1) return; // 첫 진입은 광고 스킵
    if ((_indicatorDetailOpenCount - 2) % _interstitialEvery != 0) return;
    if (!_isIndicatorInterstitialReady || _indicatorInterstitialAd == null) {
      _pendingIndicatorInterstitial = true;
      _loadIndicatorInterstitial();
      return;
    }
    _pendingIndicatorInterstitial = false;
    _showLoadedIndicatorInterstitial();
  }

  void _loadIndicatorInterstitial() {
    if (kIsWeb || !_adsEnabled) return;
    if (_isIndicatorInterstitialLoading) return;
    if (_isIndicatorInterstitialReady && _indicatorInterstitialAd != null) {
      return;
    }
    _isIndicatorInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _indicatorInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isIndicatorInterstitialLoading = false;
          _indicatorInterstitialAd?.dispose();
          _indicatorInterstitialAd = ad;
          _isIndicatorInterstitialReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _indicatorInterstitialAd = null;
              _isIndicatorInterstitialReady = false;
              _loadIndicatorInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _indicatorInterstitialAd = null;
              _isIndicatorInterstitialReady = false;
              _isIndicatorInterstitialLoading = false;
              _loadIndicatorInterstitial();
            },
          );
          if (_pendingIndicatorInterstitial &&
              !_shouldBlockByAdmin &&
              _adsEnabled) {
            _pendingIndicatorInterstitial = false;
            _showLoadedIndicatorInterstitial();
          }
        },
        onAdFailedToLoad: (_) {
          _isIndicatorInterstitialLoading = false;
          _isIndicatorInterstitialReady = false;
          _pendingIndicatorInterstitial = false;
        },
      ),
    );
  }

  void _showLoadedStockInterstitial() {
    if (!_isStockInterstitialReady || _stockInterstitialAd == null) return;
    _stockInterstitialAd!.show();
    AnalyticsService.instance.logAdInterstitialShown();
  }

  void _showLoadedIndicatorInterstitial() {
    if (!_isIndicatorInterstitialReady || _indicatorInterstitialAd == null) {
      return;
    }
    _indicatorInterstitialAd!.show();
    AnalyticsService.instance.logAdInterstitialShown();
  }

  Future<bool> showRewardedAdAndWaitReward() async {
    if (kIsWeb || !_adsEnabled || _shouldBlockByAdmin) return false;

    final completer = Completer<bool>();
    var earnedReward = false;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(earnedReward);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(
            onUserEarnedReward: (_, rewardItem) {
              earnedReward = rewardItem.amount >= 0;
            },
          );
        },
        onAdFailedToLoad: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }
}
