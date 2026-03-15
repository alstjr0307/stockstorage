import 'dart:io';
import 'package:flutter/material.dart';
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

  // 카카오 SDK 초기화
  // TODO: developers.kakao.com 에서 앱 등록 후 네이티브 앱 키를 입력하세요.
  // AndroidManifest.xml 및 Info.plist 도 함께 설정이 필요합니다.
  KakaoSdk.init(nativeAppKey: '23dd91427bb7ac2055aab304681da522');

  await NotificationService.instance.init();
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  runApp(const StockStorageApp());
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
            scaffoldBackgroundColor: const Color(0xFFF0F4F8),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4ADE80),
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
            scaffoldBackgroundColor: const Color(0xFF0A0E1A),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4ADE80),
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