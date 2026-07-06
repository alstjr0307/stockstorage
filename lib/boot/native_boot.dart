// 네이티브(iOS/Android) 전용 부트스트랩 파사드.
//
// 웹 빌드에서는 native_boot_stub.dart 가 선택되어 광고/FCM/딥링크/AppCheck 등
// 네이티브 전용 패키지를 아예 import 하지 않는다. 네이티브 빌드에서는
// dart.library.io 가 존재하므로 native_boot_io.dart 의 실제 구현이 쓰인다.
import 'native_boot_stub.dart'
    if (dart.library.io) 'native_boot_io.dart' as impl;

/// Firebase App Check 활성화(네이티브 attestation). 웹은 no-op.
Future<void> activateAppCheck() => impl.activateAppCheck();

/// FCM 백그라운드 핸들러 등록. 웹은 no-op.
void registerFcmBackgroundHandler() => impl.registerFcmBackgroundHandler();

/// 로컬 알림/FCM 초기화(runApp 이후). 웹은 no-op.
void initNotifications() => impl.initNotifications();

/// 딥링크 초기화. 웹은 no-op.
Future<void> initDeepLinks() => impl.initDeepLinks();

/// 광고 SDK + ATT 초기화. 웹은 no-op.
Future<void> initAds() => impl.initAds();
