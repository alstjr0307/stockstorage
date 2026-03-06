import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/globals.dart';
import 'firestore_service.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // iOS 권한 요청
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOS에서 APNS 토큰 대기 후 FCM 토큰 요청
    if (Platform.isIOS) {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken == null) return; // 시뮬레이터 등 APNS 미지원 환경
    }

    // FCM 토큰 저장
    final token = await messaging.getToken();
    if (token != null) {
      FirestoreService().saveFcmToken(token).catchError((_) {});
    }

    // 새 종목 알림 토픽 구독
    messaging.subscribeToTopic('stock_alerts').catchError((_) {});

    // 토큰 갱신 시 재저장
    messaging.onTokenRefresh.listen(
      (t) => FirestoreService().saveFcmToken(t).catchError((_) {}),
    );

    // 포그라운드 메시지 수신 처리
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
