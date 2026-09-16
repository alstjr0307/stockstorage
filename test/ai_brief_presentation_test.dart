import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/widgets/ai_brief_presentation.dart';

void main() {
  final now = DateTime.parse('2026-09-15T23:00:00Z');

  test('uses Korean date at 08:00 and does not call old content today', () {
    expect(
      aiBriefTimeLabel({'date': '2026-09-16', 'slotLabel': '08:00'}, now: now),
      '오늘 08:00',
    );
    expect(
      aiBriefTimeLabel({'date': '2026-09-15', 'slotLabel': '15:30'}, now: now),
      '9/15 15:30',
    );
    expect(
      aiBriefTimeLabel({'date': '2025-09-16', 'slotLabel': '09:00'}, now: now),
      '2025/9/16 09:00',
    );
  });

  test(
    'missing dates remain unknown, legacy 09 keeps its old section names',
    () {
      expect(
        aiBriefTimeLabel({'slotLabel': '09:00'}, now: now),
        contains('기준일 미상'),
      );
      expect(isMorningAiBrief({'slot': '08'}), isTrue);
      expect(isMorningAiBrief({'slot': '09'}), isFalse);
      expect(isMorningAiBrief({'slot': '12'}), isFalse);
    },
  );
}
