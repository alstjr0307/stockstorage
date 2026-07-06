// 웹 빌드용 no-op 스텁. 네이티브 전용 패키지를 전혀 import 하지 않는다.

Future<void> activateAppCheck() async {}

void registerFcmBackgroundHandler() {}

void initNotifications() {}

Future<void> initDeepLinks() async {}

Future<void> initAds() async {}
