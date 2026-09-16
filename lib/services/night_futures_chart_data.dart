import 'package:cloud_firestore/cloud_firestore.dart';

/// One minute per record: enough for the entire 18:00–05:00 session.
const nightFuturesChartRecordLimit = 720;

Query<Map<String, dynamic>> nightFuturesChartQuery(String collection) =>
    FirebaseFirestore.instance
        .collection(collection)
        .orderBy('timestamp', descending: true)
        .limit(nightFuturesChartRecordLimit);

/// Both charts display the latest recorded session, including outside hours.
/// Compare actual UTC instants; use shifted KST values only for calendar fields.
List<Map<String, dynamic>> selectNightFuturesSession(
  Iterable<Map<String, dynamic>> records,
) {
  final valid =
      records.where((record) {
        final price = record['price'];
        return record['timestamp'] is Timestamp &&
            price is num &&
            price.isFinite &&
            price > 0;
      }).toList()..sort(
        (a, b) => (a['timestamp'] as Timestamp).compareTo(
          b['timestamp'] as Timestamp,
        ),
      );
  if (valid.isEmpty) return valid;

  final latestKst = (valid.last['timestamp'] as Timestamp).toDate().toUtc().add(
    const Duration(hours: 9),
  );
  final day = latestKst.hour < 18
      ? latestKst.subtract(const Duration(days: 1))
      : latestKst;
  final startUtc = DateTime.utc(day.year, day.month, day.day, 9);
  final endUtc = startUtc.add(const Duration(hours: 11));
  return valid.where((record) {
    final time = (record['timestamp'] as Timestamp).toDate().toUtc();
    return !time.isBefore(startUtc) && time.isBefore(endUtc);
  }).toList();
}
