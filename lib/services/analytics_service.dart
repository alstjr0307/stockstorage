import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // 로그인
  Future<void> logLogin(String method) =>
      _analytics.logLogin(loginMethod: method);

  // 로그아웃
  Future<void> logLogout() =>
      _analytics.logEvent(name: 'logout');

  // 종목 상세 조회
  Future<void> logViewStock({
    required String ticker,
    required String name,
    required String market,
  }) =>
      _analytics.logViewItem(
        items: [
          AnalyticsEventItem(
            itemId: ticker,
            itemName: name,
            itemCategory: market,
          )
        ],
      );

  // 추천주 추가/제거
  Future<void> logToggleFavorite({
    required String ticker,
    required String name,
    required bool added,
  }) =>
      _analytics.logEvent(
        name: added ? 'add_to_wishlist' : 'remove_from_wishlist',
        parameters: {'ticker': ticker, 'name': name},
      );

  // 메모 저장
  Future<void> logSaveMemo(String ticker) =>
      _analytics.logEvent(
        name: 'save_memo',
        parameters: {'ticker': ticker},
      );

  // 검색
  Future<void> logSearch(String query) =>
      _analytics.logSearch(searchTerm: query);

  // 탭 전환
  Future<void> logTabChange(String tabName) =>
      _analytics.logEvent(
        name: 'tab_change',
        parameters: {'tab': tabName},
      );

  // 댓글 작성
  Future<void> logAddComment(String ticker) =>
      _analytics.logEvent(
        name: 'add_comment',
        parameters: {'ticker': ticker},
      );
}
