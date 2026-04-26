import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// 앱 시작 시 호출 — 이미 로그인된 유저 포함해서 userId 자동 연결
  void init() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _analytics.setUserId(id: user.uid);
      } else {
        _analytics.setUserId(id: null);
      }
    });
  }

  // ── 유저 ────────────────────────────────────────────────────────────────────

  Future<void> setUserId(String uid) => _analytics.setUserId(id: uid);
  Future<void> clearUserId() => _analytics.setUserId(id: null);

  Future<void> logLogin(String method) =>
      _analytics.logLogin(loginMethod: method);

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
