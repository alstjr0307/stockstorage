import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'boot/native_boot.dart' as native;
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics_service.dart';
import 'services/subscription_service.dart';
import 'web/web_shell.dart';
import 'firebase_options.dart';
import 'utils/globals.dart';

// 카카오 앱 키 (네이티브/자바스크립트). 웹은 javascriptAppKey 로 로그인.
const _kakaoNativeAppKey = '23dd91427bb7ac2055aab304681da522';
const _kakaoJavaScriptAppKey = String.fromEnvironment('KAKAO_JS_KEY');

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

  // Firebase App Check (네이티브 전용, 웹 no-op)
  await native.activateAppCheck();

  // FCM 백그라운드 핸들러 등록 (Firebase 초기화 직후, 웹 no-op)
  native.registerFcmBackgroundHandler();

  // 카카오 SDK 초기화 (웹은 javascriptAppKey 사용)
  KakaoSdk.init(
    nativeAppKey: _kakaoNativeAppKey,
    javaScriptAppKey: _kakaoJavaScriptAppKey.isEmpty
        ? _kakaoNativeAppKey
        : _kakaoJavaScriptAppKey,
  );

  AnalyticsService.instance.init();
  await SubscriptionService.instance.initialize();
  await native.initDeepLinks();
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  runApp(const StockStorageApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    native.initNotifications();
  });
}

/// 광고 초기화 진입점(홈 화면에서 호출). 웹은 no-op.
Future<void> initAds() => native.initAds();

class StockStorageApp extends StatelessWidget {
  const StockStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: SubscriptionService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProvider, child) => MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [AnalyticsService.instance.observer],
          title: '주식저장소',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          locale: const Locale('ko', 'KR'),
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
              titleTextStyle: TextStyle(
                fontFamily: 'Pretendard',
                color: Color(0xFF191F28),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
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
              titleTextStyle: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF0A0E1A),
            ),
          ),
          home: kIsWeb ? const WebShell() : const _RootGate(),
        ),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    // 이미 로그인된 유저는 온보딩 SharedPref 상태와 무관하게 항상 홈으로.
    // (앱 업데이트로 처음 새 SharedPref 키를 보게 되는 기존 유저 보호)
    if (FirebaseAuth.instance.currentUser != null) {
      return const HomeScreen();
    }
    return FutureBuilder<bool>(
      future: shouldShowOnboarding(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            ),
          );
        }
        return snapshot.data == true
            ? const OnboardingScreen()
            : const HomeScreen();
      },
    );
  }
}
