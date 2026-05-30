import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';
import '../screens/home_screen.dart';
import '../screens/journal_chart_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/stock_ai_analysis_result_screen.dart';
import '../utils/globals.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static const _journalReminderBaseId = 18000;
  final FirestoreService _firestoreService = FirestoreService();

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
    await _firestoreService.saveNotificationHistory(
      uid: uid,
      title: title,
      body: body,
      messageId: message.messageId,
      source: source,
      sentAt: message.sentTime,
      data: message.data,
    );
  }

  Future<void> _applyNewPickTopicSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final settings = await _firestoreService
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
    final settings = await _firestoreService
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
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18);
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

    try {
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 5 && apnsToken == null; i++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (apnsToken == null) {
          _firestoreService.logFcmDebug('apns_token_null');
          // APNS 토큰이 아직 없어도 초기화와 리스너 등록은 계속 진행
        }
        final token = await messaging.getToken();
        if (token != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          _firestoreService.saveFcmToken(token, uid: uid).catchError((_) {});
        } else {
          _firestoreService.logFcmDebug('fcm_token_null, apns=$apnsToken');
        }
      } else {
        final token = await messaging.getToken();
        if (token != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          _firestoreService.saveFcmToken(token, uid: uid).catchError((_) {});
        }
      }
    } catch (e) {
      _firestoreService.logFcmDebug('exception: $e');
    }

    // 종목 알림 토픽 구독
    messaging.subscribeToTopic('stock_alerts').catchError((_) {});
    _applyNewPickTopicSubscription().catchError((_) {});
    _applyJournalWriteReminderSchedule().catchError((_) {});

    messaging.onTokenRefresh.listen((t) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      _firestoreService.saveFcmToken(t, uid: uid).catchError((_) {});
    });

    // 로그인 시점에도 토큰 저장
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await messaging.getToken();
        if (token != null) {
          _firestoreService
              .saveFcmToken(token, uid: user.uid)
              .catchError((_) {});
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
      _saveRemoteMessageHistory(
        message,
        source: 'foreground',
      ).catchError((_) {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context == null) return;
        _showSnackBar(context, title, body, message);
      });
    });

    // 백그라운드에서 알림을 눌러 진입
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _saveRemoteMessageHistory(
        message,
        source: 'opened_app',
      ).catchError((_) {});
      _handleNotificationTap(message);
    });

    // 종료 상태에서 알림을 눌러 진입
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _saveRemoteMessageHistory(
        initialMessage,
        source: 'opened_from_terminated',
      ).catchError((_) {});
      _handleNotificationTap(initialMessage);
    }
  }

  Future<BuildContext?> _waitForNavigatorContext() async {
    for (var i = 0; i < 20; i++) {
      final context = navigatorKey.currentContext;
      if (context != null) return context;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _handleNotificationTap(RemoteMessage message) async {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final postId = (data['postId'] ?? '').toString();
    final pickId = (data['pickId'] ?? '').toString();
    final journalId = (data['journalId'] ?? '').toString();

    if (type == 'ai_analysis_complete') {
      await _openAiAnalysisResult(
        ticker: (data['ticker'] ?? '').toString(),
        market: (data['market'] ?? '').toString(),
        name: (data['name'] ?? '').toString(),
      );
      return;
    }
    if (postId.isNotEmpty) {
      await _openPost(postId);
      return;
    }
    if (pickId.isNotEmpty) {
      await _openPickList();
      return;
    }
    if (journalId.isNotEmpty) {
      await _openJournal(journalId);
    }
  }

  Future<void> _openAiAnalysisResult({
    required String ticker,
    required String market,
    required String name,
  }) async {
    await _waitForNavigatorContext();
    if (ticker.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final normalizedMarket = market.trim().toUpperCase();
    final normalizedTicker = ticker.trim().toUpperCase();
    final resolvedMarket = normalizedMarket.isEmpty ? 'KS' : normalizedMarket;
    final analysisId = '${resolvedMarket}_$normalizedTicker';
    final routeName = 'stock-ai-analysis:$analysisId';

    // 같은 종목 분석 화면이 이미 스택에 있으면 새로 push하지 않고 그 화면으로 돌아간다.
    // (분석 중 앱을 백그라운드로 보낸 뒤 푸시 탭 → 같은 화면 두 개 쌓이는 문제 방지)
    var foundExisting = false;
    navigator.popUntil((route) {
      if (route.settings.name == routeName) {
        foundExisting = true;
        return true;
      }
      return route.isFirst;
    });
    if (foundExisting) return;

    final pick = StockPick(
      id: 'stock_$analysisId',
      ticker: normalizedTicker,
      name: name.isEmpty ? normalizedTicker : name,
      buyPrice: 0,
      targetPrice: 0,
      reason: '',
      category: '단기',
      market: resolvedMarket,
      isPremium: false,
      createdAt: DateTime.now(),
      status: 'active',
    );
    navigator.push(
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (_) => StockAiAnalysisResultScreen(pick: pick),
      ),
    );
  }

  Future<void> _openPost(String postId) async {
    final context = await _waitForNavigatorContext();
    if (context == null) return;
    final post = await _firestoreService.getPostOnce(postId);
    if (post == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('게시글을 찾을 수 없습니다.')));
      }
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isLiked = uid == null || uid.isEmpty
        ? false
        : await _firestoreService.hasLikedPost(post.id, uid);
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          isOwn: uid != null && uid == post.uid,
          isLiked: isLiked,
          likeCount: post.likes,
          onDelete: uid != null && uid == post.uid
              ? () => _firestoreService.deletePost(post.id)
              : null,
        ),
      ),
    );
  }

  Future<void> _openPickList() async {
    await _waitForNavigatorContext();
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const StockPicksListScreen()),
    );
  }

  Future<void> _openJournal(String journalId) async {
    final context = await _waitForNavigatorContext();
    if (context == null) return;
    final journal = await _firestoreService.getJournalById(journalId);
    if (journal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('매매일지를 찾을 수 없습니다.')));
      }
      return;
    }
    final publicByAuthor = await _firestoreService.getPublicJournalsByUidOnce(
      journal.uid,
    );
    final relatedBuys =
        publicByAuthor
            .where(
              (j) =>
                  j.action == '\uB9E4\uC218' &&
                  j.ticker == journal.ticker &&
                  j.market == journal.market,
            )
            .toList()
          ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    final relatedSells =
        publicByAuthor
            .where(
              (j) =>
                  j.action == '\uB9E4\uB3C4' &&
                  j.ticker == journal.ticker &&
                  j.market == journal.market,
            )
            .toList()
          ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    final chartBaseBuy = journal.action == '\uB9E4\uC218'
        ? journal
        : _selectChartBaseBuy(journal, relatedBuys);
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => JournalChartScreen(
          buy: chartBaseBuy,
          linkedSells: const <TradingJournal>[],
          relatedBuys: relatedBuys,
          relatedSells: relatedSells,
          showBuyMarker: relatedBuys.isNotEmpty,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }

  TradingJournal _selectChartBaseBuy(
    TradingJournal journal,
    List<TradingJournal> relatedBuys,
  ) {
    TradingJournal? latestBefore;
    for (final buy in relatedBuys) {
      if (!buy.tradeDate.isAfter(journal.tradeDate)) latestBefore = buy;
    }
    if (latestBefore != null) return latestBefore;
    if (relatedBuys.isNotEmpty) return relatedBuys.first;
    return TradingJournal(
      id: 'synthetic_buy_${journal.id}',
      uid: journal.uid,
      nickname: journal.nickname,
      stockName: journal.stockName,
      ticker: journal.ticker,
      market: journal.market,
      action: '\uB9E4\uC218',
      price: journal.buyPrice > 0 ? journal.buyPrice : journal.price,
      quantity: journal.quantity,
      tradeDate: journal.tradeDate,
      note: '',
      isPublic: false,
      likes: 0,
      createdAt: journal.createdAt,
    );
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

  void _showSnackBar(
    BuildContext context,
    String title,
    String body,
    RemoteMessage message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _handleNotificationTap(message);
          },
          child: Column(
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
                Text(
                  body,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFF1A2035),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
