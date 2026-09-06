import 'package:cloud_firestore/cloud_firestore.dart';

/// 코스피200 옵션 Max Pain 캐시 (서버 kospi200_maxpain/latest 문서).
class Kospi200MaxPain {
  final String expiry; // YYYYMM
  final String expiryDate; // YYYY-MM-DD (2번째 목요일)
  final double maxPain;
  final double? atmStrike;
  final double? currentLevel;
  final int totalCallOi;
  final int totalPutOi;
  final double? putCallRatio;
  final List<Kospi200OiStrike> strikes;
  final DateTime? updatedAt;

  const Kospi200MaxPain({
    required this.expiry,
    required this.expiryDate,
    required this.maxPain,
    required this.atmStrike,
    required this.currentLevel,
    required this.totalCallOi,
    required this.totalPutOi,
    required this.putCallRatio,
    required this.strikes,
    required this.updatedAt,
  });

  static Kospi200MaxPain? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final rawStrikes = (d['strikes'] as List?) ?? const [];
    return Kospi200MaxPain(
      expiry: (d['expiry'] as String?) ?? '',
      expiryDate: (d['expiryDate'] as String?) ?? '',
      maxPain: (d['maxPain'] as num?)?.toDouble() ?? 0,
      atmStrike: (d['atmStrike'] as num?)?.toDouble(),
      currentLevel: (d['currentLevel'] as num?)?.toDouble(),
      totalCallOi: (d['totalCallOi'] as num?)?.toInt() ?? 0,
      totalPutOi: (d['totalPutOi'] as num?)?.toInt() ?? 0,
      putCallRatio: (d['putCallRatio'] as num?)?.toDouble(),
      strikes: [
        for (final s in rawStrikes)
          if (s is Map)
            Kospi200OiStrike(
              strike: (s['strike'] as num?)?.toDouble() ?? 0,
              callOi: (s['callOi'] as num?)?.toInt() ?? 0,
              putOi: (s['putOi'] as num?)?.toInt() ?? 0,
            ),
      ],
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// 차트/괴리율 기준선. 옵션 체인과 정합하도록 ATM 행사가를 우선 사용
  /// (외부 지수는 소스가 달라 어긋날 수 있음). ATM → 현재가 → Max Pain 폴백.
  double get referenceLevel => atmStrike ?? currentLevel ?? maxPain;

  /// 만기까지 D-day (음수면 당일/경과).
  int get daysToExpiry {
    final parts = expiryDate.split('-');
    if (parts.length != 3) return 0;
    final exp = DateTime.tryParse(expiryDate);
    if (exp == null) return 0;
    final now = DateTime.now();
    return DateTime(
      exp.year,
      exp.month,
      exp.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }
}

class Kospi200OiStrike {
  final double strike;
  final int callOi;
  final int putOi;

  const Kospi200OiStrike({
    required this.strike,
    required this.callOi,
    required this.putOi,
  });
}
