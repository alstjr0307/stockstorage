import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/night_futures_chart_data.dart';

Map<String, dynamic> quote(String time, double price) => {
  'timestamp': Timestamp.fromDate(DateTime.parse(time)),
  'price': price,
};

void main() {
  for (final market in [
    'night_futures_prices',
    'night_futures_prices_kosdaq',
  ]) {
    test('$market retains the full overnight session beyond 40 records', () {
      final start = DateTime.utc(2026, 9, 15, 9);
      final records = List.generate(
        660,
        (i) => {
          'timestamp': Timestamp.fromDate(start.add(Duration(minutes: i))),
          'price': 400.0 + i,
        },
      );
      final session = selectNightFuturesSession([
        ...records.reversed,
        quote('2026-09-15T04:59:00+09:00', 399),
      ]);
      expect(nightFuturesChartRecordLimit, greaterThanOrEqualTo(660));
      expect(session, hasLength(660));
      expect(session.first['price'], 400);
      expect(session.last['price'], 1059);
    });
  }

  test(
    'KST 18:00 boundary excludes the preceding session, across midnight',
    () {
      final session = selectNightFuturesSession([
        quote('2026-09-16T00:01:00+09:00', 403),
        quote('2026-09-15T17:59:59+09:00', 399),
        quote('2026-09-15T18:00:00+09:00', 400),
        quote('2026-09-15T23:59:00+09:00', 402),
      ]);
      expect(session.map((row) => row['price']), [400, 402, 403]);
    },
  );

  test('a new 18:00 session drops all preceding overnight points', () {
    final session = selectNightFuturesSession([
      quote('2026-09-16T04:59:00+09:00', 400),
      quote('2026-09-16T18:00:00+09:00', 410),
    ]);
    expect(session.map((row) => row['price']), [410]);
  });

  test('UTC and offset timestamps describe the same session', () {
    final session = selectNightFuturesSession([
      quote('2026-09-15T09:00:00Z', 400),
      quote('2026-09-16T04:59:00+09:00', 410),
      quote('2026-09-15T04:59:00+09:00', 390),
    ]);
    expect(session.map((row) => row['price']), [400, 410]);
  });

  test('latest recorded session remains available without current trades', () {
    final session = selectNightFuturesSession([
      quote('2026-09-11T18:00:00+09:00', 400),
      quote('2026-09-12T04:59:00+09:00', 410),
    ]);
    expect(session, hasLength(2));
  });

  test('invalid records cannot move the session or distort either chart', () {
    final session = selectNightFuturesSession([
      quote('2026-09-15T18:00:00+09:00', 400),
      quote('2026-09-16T18:00:00+09:00', 0),
      quote('2026-09-16T18:00:00+09:00', double.nan),
      quote('2026-09-16T18:00:00+09:00', double.infinity),
      {'price': 410},
    ]);
    expect(session.map((row) => row['price']), [400]);
    expect(selectNightFuturesSession([]), isEmpty);
    expect(
      selectNightFuturesSession([
        {'price': 410},
      ]),
      isEmpty,
    );
  });
}
