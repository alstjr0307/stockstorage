import 'package:cloud_firestore/cloud_firestore.dart';

enum CalendarEventType { earnings, economic, ipo, unknown }

CalendarEventType _typeFromString(String? v) {
  switch (v) {
    case 'earnings':
      return CalendarEventType.earnings;
    case 'economic':
      return CalendarEventType.economic;
    case 'ipo':
      return CalendarEventType.ipo;
    default:
      return CalendarEventType.unknown;
  }
}

/// market_calendar/{eventId} — 자동 수집된 경제·실적·IPO 일정.
class MarketCalendarEvent {
  final String id;
  final CalendarEventType type;
  final String country; // 'US' | 'KR'
  final String date; // 'YYYY-MM-DD'
  final DateTime? timestamp;
  final String? symbol;
  final String? name;
  final String title;
  final int importance; // 0~3 (3 = 가장 중요)
  final Map<String, dynamic> extra;

  MarketCalendarEvent({
    required this.id,
    required this.type,
    required this.country,
    required this.date,
    required this.title,
    required this.importance,
    this.timestamp,
    this.symbol,
    this.name,
    this.extra = const {},
  });

  factory MarketCalendarEvent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return MarketCalendarEvent(
      id: doc.id,
      type: _typeFromString(d['type'] as String?),
      country: d['country'] as String? ?? 'US',
      date: d['date'] as String? ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      symbol: d['symbol'] as String?,
      name: d['name'] as String?,
      title: d['title'] as String? ?? '',
      importance: (d['importance'] as num?)?.toInt() ?? 0,
      extra: (d['extra'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// 'YYYY-MM-DD' → DateTime (정렬·그룹핑용; timestamp 없을 때 폴백)
  DateTime get dateTime {
    if (timestamp != null) return timestamp!;
    final parts = date.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final dd = int.tryParse(parts[2]);
      if (y != null && m != null && dd != null) return DateTime(y, m, dd);
    }
    return DateTime.now();
  }
}
