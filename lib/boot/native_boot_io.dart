// 네이티브(iOS/Android) 실제 부트스트랩 구현.
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';

Future<void> activateAppCheck() async {
  // Debug provider 토큰은 앱 데이터 초기화 때마다 바뀔 수 있어 로컬 개발 중에는
  // App Check를 켜지 않는다. 릴리즈 빌드에서만 실제 attestation을 사용한다.
  if (kDebugMode) return;
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  } catch (_) {
    // 에뮬레이터 등 지원 안 되는 환경에서 무시
  }
}

void registerFcmBackgroundHandler() {
  NotificationService.registerBackgroundHandler();
}

void initNotifications() {
  NotificationService.instance.init();
}

Future<void> initDeepLinks() => DeepLinkService.init();

Future<void> initAds() async {
  if (Platform.isIOS) {
    // UI가 완전히 로드된 후 ATT 팝업 표시 (Apple 심사 요건)
    await Future.delayed(const Duration(milliseconds: 300));
    var status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      status = await AppTrackingTransparency.requestTrackingAuthorization();
    }
    // ATT 동의 여부를 Meta SDK에 전달 (광고 식별자 추적 허용 여부)
    await AnalyticsService.instance.setAdvertiserTracking(
      status == TrackingStatus.authorized,
    );
  }
  await MobileAds.instance.initialize();
  AdService.instance.loadInterstitial();
}
