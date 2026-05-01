import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
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
  static const _journalReminderBaseId = 18000;

  Future<void> _saveRemoteMessageHistory(
    RemoteMessage message, {
    required String source,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final title = (message.notification?.title ?? message.data['title'] ?? '')
        .toString();
    final body = (message.notification?.body ?? message.data['body'] ?? '')
        .toString();
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    await FirestoreService().saveNotificationHistory(
      uid: uid,
      title: title,
      body: body,
      messageId: message.messageId,
      source: source,
      sentAt: message.sentTime,
    );
  }

  Future<void> _applyNewPickTopicSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final settings = await FirestoreService()
        .ensureNotificationSettingsInitialized(user.uid);
    final enabled = settings['newPick'] ?? true;
    if (enabled) {
      await FirebaseMessaging.instance.subscribeToTopic('new_pick_alerts');
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic('new_pick_alerts');
    }
  }

  Future<void> _applyJournalWriteReminderSchedule() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final settings = await FirestoreService()
        .ensureNotificationSettingsInitialized(user.uid);
    final enabled = settings['journalWriteReminder'] ?? false;
    if (enabled) {
      await scheduleWeekdayJournalWriteReminder();
    } else {
      await cancelWeekdayJournalWriteReminder();
    }
  }

  static tz.TZDateTime _nextWeekdayAt18(int weekday) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      18,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static Future<void> scheduleWeekdayJournalWriteReminder() async {
    const android = AndroidNotificationDetails(
      'journal_write_reminder',
      '매매일지 리마인더',
      channelDescription: '평일 오후 6시 매매일지 작성 알림',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: android,
      iOS: DarwinNotificationDetails(),
    );

    for (var weekday = DateTime.monday; weekday <= DateTime.friday; weekday++) {
      await _localNotifications.zonedSchedule(
        _journalReminderBaseId + weekday,
        '매매일지 작성 시간',
        '오늘 매매일지를 기록해보세요.',
        _nextWeekdayAt18(weekday),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static Future<void> cancelWeekdayJournalWriteReminder() async {
    for (var weekday = DateTime.monday; weekday <= DateTime.friday; weekday++) {
      await _localNotifications.cancel(_journalReminderBaseId + weekday);
    }
  }

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
    tzdata.initializeTimeZones();

    // FCM 토큰 저장: iOS는 APNS 토큰 준비까지 최대 5초 대기
    try {
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 5 && apnsToken == null; i++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        final db = FirestoreService();
        if (apnsToken == null) {
          db.logFcmDebug('apns_token_null');
          // APNS 토큰이 아직 없어도 나머지 초기화(토픽/리스너)는 계속 진행
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

    // 종목 알림 토픽 구독
    messaging.subscribeToTopic('stock_alerts').catchError((_) {});
    _applyNewPickTopicSubscription().catchError((_) {});
    _applyJournalWriteReminderSchedule().catchError((_) {});

    // 토큰 갱신 시 저장
    messaging.onTokenRefresh.listen((t) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      FirestoreService().saveFcmToken(t, uid: uid).catchError((_) {});
    });

    // 로그인 시점에도 토큰 저장 (앱 시작 후 지연 로그인 대비)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await messaging.getToken();
        if (token != null) {
          FirestoreService().saveFcmToken(token, uid: user.uid).catchError((_) {});
        }
        _applyNewPickTopicSubscription().catchError((_) {});
        _applyJournalWriteReminderSchedule().catchError((_) {});
      } catch (_) {}
    });

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;
      _saveRemoteMessageHistory(message, source: 'foreground').catchError((_) {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context == null) return;
        _showSnackBar(context, title, body);
      });
    });

    // 백그라운드에서 알림 탭해 앱 진입
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _saveRemoteMessageHistory(message, source: 'opened_app').catchError((_) {});
    });

    // 종료 상태에서 알림 탭해 앱 진입
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _saveRemoteMessageHistory(
        initialMessage,
        source: 'opened_from_terminated',
      ).catchError((_) {});
    }
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
      '현재 수익률 $sign${returnRate.toStringAsFixed(1)}%',
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
