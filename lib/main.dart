import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'services/analytics_service.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';
import 'utils/globals.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Firebase App Check 초기화 (디버그/에뮬레이터는 debug 프로바이더)
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck,
    );
  } catch (_) {
    // 에뮬레이터 등 지원 안 되는 환경에서 무시
  }

  // FCM 백그운드 핸들러 등록 (Firebase 초기화 직후)
  NotificationService.registerBackgroundHandler();

  // 카카오 SDK 초기화
  KakaoSdk.init(nativeAppKey: '23dd91427bb7ac2055aab304681da522');

  AnalyticsService.instance.init();
  await DeepLinkService.init();
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  runApp(const StockStorageApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.instance.init();
  });
}

Future<void> initAds() async {
  if (Platform.isIOS) {
    // UI가 완전히 로드된 후 ATT 팝업 표시 (Apple 심사 요건)
    await Future.delayed(const Duration(milliseconds: 300));
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }
  await MobileAds.instance.initialize();
  AdService.instance.loadInterstitial();
}

class StockStorageApp extends StatelessWidget {
  const StockStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProvider, child) => MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [AnalyticsService.instance.observer],
          title: '주식저장소',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          // 라이트 테마
          theme: ThemeData(
            brightness: Brightness.light,
            fontFamily: 'Pretendard',
            textTheme: ThemeData.light().textTheme.apply(
              fontFamily: 'Pretendard',
            ),
            scaffoldBackgroundColor: const Color(0xFFF0F4F8),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
              brightness: Brightness.light,
              surface: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF0F4F8),
              elevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFFF0F4F8),
            ),
          ),
          // 다크 테마
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'Pretendard',
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'Pretendard',
            ),
            scaffoldBackgroundColor: const Color(0xFF0A0E1A),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
              brightness: Brightness.dark,
              surface: const Color(0xFF1A2035),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0A0E1A),
              elevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF0A0E1A),
            ),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
