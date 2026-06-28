import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  /// Meta(Facebook) 앱 이벤트 — 설치 광고 추적/최적화용.
  /// 앱 실행(활성화) 이벤트는 SDK가 자동 기록한다.
  final _fb = FacebookAppEvents();

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// 앱 시작 시 호출 — 이미 로그인된 유저 포함해서 userId 자동 연결
  void init() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _analytics.setUserId(id: user.uid);
        _fb.setUserID(user.uid);
      } else {
        _analytics.setUserId(id: null);
        _fb.clearUserID();
      }
    });
  }

  /// iOS ATT 동의 결과를 Meta SDK에 전달 (광고 식별자 추적 허용 여부).
  /// Android에서는 호출해도 무해하다.
  Future<void> setAdvertiserTracking(bool enabled) =>
      _fb.setAdvertiserTracking(enabled: enabled);

  // ── 유저 ────────────────────────────────────────────────────────────────────

  Future<void> setUserId(String uid) {
    _fb.setUserID(uid);
    return _analytics.setUserId(id: uid);
  }

  Future<void> clearUserId() {
    _fb.clearUserID();
    return _analytics.setUserId(id: null);
  }

  Future<void> logLogin(String method) =>
      _analytics.logLogin(loginMethod: method);

  /// 신규 회원가입 — Firebase `sign_up` + Meta `CompleteRegistration`.
  /// Meta 가입 전환 캠페인 최적화에 사용된다.
  Future<void> logSignUp(String method) async {
    await _analytics.logSignUp(signUpMethod: method);
    await _fb.logCompletedRegistration(registrationMethod: method);
  }

  Future<void> logLogout() => _analytics.logEvent(name: 'logout');

  // ── 화면 ────────────────────────────────────────────────────────────────────

  Future<void> logScreenView(String screenName) =>
      _analytics.logScreenView(screenName: screenName);

  Future<void> logTabChange(String tabName) =>
      _analytics.logEvent(name: 'tab_change', parameters: {'tab': tabName});

  // ── 종목 ────────────────────────────────────────────────────────────────────

  Future<void> logViewStock({
    required String ticker,
    required String name,
    required String market,
  }) => _analytics.logViewItem(
    items: [
      AnalyticsEventItem(itemId: ticker, itemName: name, itemCategory: market),
    ],
  );

  Future<void> logToggleFavorite({
    required String ticker,
    required String name,
    required bool added,
  }) => _analytics.logEvent(
    name: added ? 'add_to_wishlist' : 'remove_from_wishlist',
    parameters: {'ticker': ticker, 'name': name},
  );

  Future<void> logSearch(String query) =>
      _analytics.logSearch(searchTerm: query);

  Future<void> logSaveMemo(String ticker) =>
      _analytics.logEvent(name: 'save_memo', parameters: {'ticker': ticker});

  Future<void> logAddComment(String ticker) =>
      _analytics.logEvent(name: 'add_comment', parameters: {'ticker': ticker});

  Future<void> logViewIndexDetail(String name) => _analytics.logEvent(
    name: 'view_index_detail',
    parameters: {'index_name': name},
  );

  Future<void> logViewNightFutures() =>
      _analytics.logEvent(name: 'view_night_futures');

  // ── 매매일지 ─────────────────────────────────────────────────────────────────

  /// action: '매수' | '매도' | '관찰'
  Future<void> logWriteJournal(String action) => _analytics.logEvent(
    name: 'write_journal',
    parameters: {'action': action},
  );

  Future<void> logEditJournal() => _analytics.logEvent(name: 'edit_journal');

  Future<void> logDeleteJournal() =>
      _analytics.logEvent(name: 'delete_journal');

  Future<void> logToggleJournalPublic(bool isPublic) => _analytics.logEvent(
    name: 'toggle_journal_public',
    parameters: {'is_public': isPublic ? 'true' : 'false'},
  );

  Future<void> logViewJournalChart() =>
      _analytics.logEvent(name: 'view_journal_chart');

  // ── 커뮤니티 ─────────────────────────────────────────────────────────────────

  /// type: 'journal' | 'post'
  Future<void> logLikeContent(String type) =>
      _analytics.logEvent(name: 'like_content', parameters: {'type': type});

  Future<void> logWritePost() => _analytics.logEvent(name: 'write_post');

  Future<void> logEditPost() => _analytics.logEvent(name: 'edit_post');

  Future<void> logDeletePost() => _analytics.logEvent(name: 'delete_post');

  /// contentType: 'journal' | 'post' | 'comment'
  Future<void> logWriteCommunityComment(String contentType) =>
      _analytics.logEvent(
        name: 'write_community_comment',
        parameters: {'content_type': contentType},
      );

  /// contentType: 'journal' | 'post' | 'comment'
  Future<void> logReportContent(String contentType) => _analytics.logEvent(
    name: 'report_content',
    parameters: {'content_type': contentType},
  );

  Future<void> logBlockUser() => _analytics.logEvent(name: 'block_user');

  // ── 광고 ─────────────────────────────────────────────────────────────────

  Future<void> logAdInterstitialShown() =>
      _analytics.logEvent(name: 'ad_interstitial_shown');
}
