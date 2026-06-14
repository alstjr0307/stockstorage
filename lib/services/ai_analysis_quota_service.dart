import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 레벨 기반 일일 AI 분석 횟수 제한.
/// 카운터는 users/{uid}/ai_quota/{YYYY-MM-DD} 문서에 기록한다.
class AiAnalysisQuotaService {
  AiAnalysisQuotaService._();
  static final instance = AiAnalysisQuotaService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 레벨에 따른 하루 최대 횟수.
  static int dailyLimitForLevel(int level) {
    if (level >= 20) return 5;
    if (level >= 10) return 3;
    if (level >= 5) return 2;
    return 1;
  }

  String _todayKey() {
    // 서버는 Asia/Seoul 기준 날짜키로 카운트를 기록한다 (functions/index.js seoulDateKey).
    // 클라이언트도 동일하게 KST(UTC+9, DST 없음)로 고정해 doc 키가 어긋나지 않도록 한다.
    final seoul = DateTime.now().toUtc().add(const Duration(hours: 9));
    final y = seoul.year.toString().padLeft(4, '0');
    final m = seoul.month.toString().padLeft(2, '0');
    final d = seoul.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DocumentReference<Map<String, dynamic>> _docRef(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('ai_quota')
        .doc(_todayKey());
  }

  Stream<int> watchUsedToday(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _docRef(
      uid,
    ).snapshots().map((doc) => (doc.data()?['count'] as num?)?.toInt() ?? 0);
  }

  Future<int> getUsedToday(String uid) async {
    if (uid.isEmpty) return 0;
    final doc = await _docRef(uid).get();
    return (doc.data()?['count'] as num?)?.toInt() ?? 0;
  }
}
