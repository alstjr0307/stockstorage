import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/globals.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 메시지는 시스템 알림으로 자동 표시되므로 별도 처리 불필요
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final messaging = FirebaseMessaging.instance;

    // iOS 권한 요청
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // iOS 포그라운드 알림 배너 표시
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 로컬 알림 초기화
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);

    // FCM 토큰 저장 — iOS는 APNS 토큰이 준비될 때까지 최대 5초 대기
    try {
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 5 && apnsToken == null; i++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null)
            await Future.delayed(const Duration(seconds: 1));
        }
        final db = FirestoreService();
        if (apnsToken == null) {
          db.logFcmDebug('apns_token_null');
          return;
        }
        final token = await messaging.getToken();
        if (token != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          FirestoreService().saveFcmToken(token, uid: uid).catchError((_) {});
        } else {
          db.logFcmDebug('fcm_token_null, apns=$apnsToken');
        }
      } else {
        final token = await messaging.getToken();
        if (token != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          FirestoreService().saveFcmToken(token, uid: uid).catchError((_) {});
        }
      }
    } catch (e) {
      FirestoreService().logFcmDebug('exception: $e');
    }

    // 새 종목 알림 토픽 구독
    messaging.subscribeToTopic('stock_alerts').catchError((_) {});

    // 토큰 갱신 시 재저장
    messaging.onTokenRefresh.listen((t) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      FirestoreService().saveFcmToken(t, uid: uid).catchError((_) {});
    });

    // 로그인 시점에 토큰 재저장 (앱 시작 시 미로그인 상태로 저장 실패한 경우 대비)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await messaging.getToken();
        if (token != null) {
          FirestoreService()
              .saveFcmToken(token, uid: user.uid)
              .catchError((_) {});
        }
      } catch (_) {}
    });

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context == null) return;
        _showSnackBar(context, title, body);
      });
    });

    // 백그라운드에서 알림 탭해서 앱 진입
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {});

    // 종료 상태에서 알림 탭해서 앱 진입
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {}
  }

  /// 포트폴리오 10% 구간 도달 로컬 알림
  static Future<void> showPortfolioAlert(
    String stockName,
    double returnRate,
  ) async {
    final isPositive = returnRate >= 0;
    final threshold = (returnRate / 10).truncate() * 10;
    final emoji = isPositive ? '📈' : '📉';
    final sign = isPositive ? '+' : '';
    await _localNotifications.show(
      stockName.hashCode.abs() % 10000,
      '$emoji $stockName $sign${threshold.toInt()}% 구간 도달',
      '현재 수익률: $sign${returnRate.toStringAsFixed(1)}%',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'stockstorage_alerts',
          '주식 알림',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String title, String body) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            if (body.isNotEmpty)
              Text(body, style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF1A2035),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
