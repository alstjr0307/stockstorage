import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockstorage/services/premium_nudge_service.dart';

void main() {
  const spot = PremiumNudgeService.reportFooter;
  final service = PremiumNudgeService.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('처음에는 노출된다', () async {
    expect(await service.shouldShow(spot), isTrue);
  });

  test('노출 직후에는 다시 뜨지 않는다', () async {
    await service.markShown(spot);
    expect(await service.shouldShow(spot), isFalse);
  });

  test('닫으면 일반 간격보다 훨씬 오래 쉬어간다', () async {
    await service.markShown(spot);
    final afterShown = SharedPreferences.getInstance().then(
      (p) => p.getInt('premium_nudge_${spot.key}')!,
    );
    await service.markDismissed(spot);
    final afterDismissed = SharedPreferences.getInstance().then(
      (p) => p.getInt('premium_nudge_${spot.key}')!,
    );
    expect(await afterDismissed, greaterThan(await afterShown));
    expect(await service.shouldShow(spot), isFalse);
  });

  test('간격이 지나면 다시 노출된다', () async {
    final prefs = await SharedPreferences.getInstance();
    // 재노출 시점이 이미 지난 상태를 흉내낸다.
    await prefs.setInt(
      'premium_nudge_${spot.key}',
      DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    );
    expect(await service.shouldShow(spot), isTrue);
  });

  test('닫기 간격이 일반 노출 간격보다 길게 설정돼 있다', () {
    expect(spot.snooze, greaterThan(spot.interval));
  });
}
