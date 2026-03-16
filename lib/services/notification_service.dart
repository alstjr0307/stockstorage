import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final messaging = FirebaseMessaging.instance;

    // iOS 권한 요청
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // FCM 토큰 저장 — iOS는 APNS 토큰이 없으면 건너뜀
    try {
      if (Platform.isIOS) {
        final apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) {
          final token = await messaging.getToken();
          if (token != null) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            FirestoreService().saveFcmToken(token, uid: uid).catchError((_) {});
          }
        }
      } else {
        final token = await messaging.getToken();
        if (token != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          FirestoreService().saveFcmToken(token, uid: uid).catchError((_) {});
        }
      }
    } catch (_) {
      // SERVICE_NOT_AVAILABLE 등 FCM 미지원 환경
    }

    // 새 종목 알림 토픽 구독
    messaging.subscribeToTopic('stock_alerts').catchError((_) {});

    // 토큰 갱신 시 재저장
    messaging.onTokenRefresh.listen((t) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      FirestoreService().saveFcmToken(t, uid: uid).catchError((_) {});
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
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // 필요 시 특정 화면으로 이동 가능
    });

    // 종료 상태에서 알림 탭해서 앱 진입
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      // 필요 시 특정 화면으로 이동 가능
    }
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
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            if (body.isNotEmpty)
              Text(
                body,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF1A2035),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
