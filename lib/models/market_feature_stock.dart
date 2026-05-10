import 'package:cloud_firestore/cloud_firestore.dart';

class MarketFeatureStock {
  final String id;
  final String ticker;
  final String name;
  final String market;
  final String group;
  final String pattern;
  final String title;
  final String reason;
  final double price;
  final double changeRate;
  final int score;
  final int tradingValue;
  final double volumeRatio;
  final DateTime sourceDate;
  final DateTime createdAt;

  const MarketFeatureStock({
    required this.id,
    required this.ticker,
    required this.name,
    required this.market,
    required this.group,
    required this.pattern,
    required this.title,
    required this.reason,
    required this.price,
    required this.changeRate,
    required this.score,
    required this.tradingValue,
    required this.volumeRatio,
    required this.sourceDate,
    required this.createdAt,
  });

  factory MarketFeatureStock.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MarketFeatureStock(
      id: doc.id,
      ticker: data['ticker'] ?? '',
      name: data['name'] ?? '',
      market: data['market'] ?? 'KR',
      group: data['group'] ?? 'chart_capture',
      pattern: data['pattern'] ?? '',
      title: data['title'] ?? '',
      reason: data['reason'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      changeRate: (data['changeRate'] ?? 0).toDouble(),
      score: (data['score'] ?? 0).toInt(),
      tradingValue: (data['tradingValue'] ?? 0).toInt(),
      volumeRatio: (data['volumeRatio'] ?? 0).toDouble(),
      sourceDate:
          (data['sourceDate'] as Timestamp?)?.toDate() ?? DateTime(1970),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970),
    );
  }
}
