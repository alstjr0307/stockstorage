import 'package:shared_preferences/shared_preferences.dart';

/// 프리미엄 유도 노출 빈도 관리.
///
/// 같은 자리에서 매번 뜨면 그 자체가 광고처럼 느껴져 역효과가 난다.
/// 지점별로 최소 재노출 간격을 두고, 사용자가 직접 닫으면 훨씬 길게 쉬어간다.
class PremiumNudgeSpot {
  const PremiumNudgeSpot(
    this.key, {
    required this.interval,
    required this.snooze,
  });

  final String key;

  /// 그냥 노출된 뒤 다음 노출까지의 최소 간격.
  final Duration interval;

  /// 사용자가 직접 닫았을 때의 재노출 간격.
  final Duration snooze;
}

class PremiumNudgeService {
  PremiumNudgeService._();
  static final instance = PremiumNudgeService._();

  /// AI 리포트를 끝까지 읽은 뒤 하단에 뜨는 카드.
  static const reportFooter = PremiumNudgeSpot(
    'report_footer',
    interval: Duration(days: 1),
    snooze: Duration(days: 14),
  );

  static const _prefix = 'premium_nudge_';

  Future<bool> shouldShow(PremiumNudgeSpot spot) async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt('$_prefix${spot.key}');
    if (until == null) return true;
    return DateTime.now().millisecondsSinceEpoch >= until;
  }

  Future<void> markShown(PremiumNudgeSpot spot) => _defer(spot, spot.interval);

  Future<void> markDismissed(PremiumNudgeSpot spot) =>
      _defer(spot, spot.snooze);

  Future<void> _defer(PremiumNudgeSpot spot, Duration by) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_prefix${spot.key}',
      DateTime.now().add(by).millisecondsSinceEpoch,
    );
  }
}
