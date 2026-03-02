import 'package:cloud_firestore/cloud_firestore.dart';

class StockPick {
  final String id;
  final String ticker;
  final String name;
  final double buyPrice;
  final double targetPrice;
  final String reason;
  final String category; // 단기, 중기, 장기
  final bool isPremium;
  final DateTime createdAt;
  final String? imageUrl;
  double? currentPrice;

  StockPick({
    required this.id,
    required this.ticker,
    required this.name,
    required this.buyPrice,
    required this.targetPrice,
    required this.reason,
    required this.category,
    required this.isPremium,
    required this.createdAt,
    this.imageUrl,
    this.currentPrice,
  });

  double get returnRate => ((targetPrice - buyPrice) / buyPrice) * 100;

  factory StockPick.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StockPick(
      id: doc.id,
      ticker: data['ticker'] ?? '',
      name: data['name'] ?? '',
      buyPrice: (data['buyPrice'] ?? 0).toDouble(),
      targetPrice: (data['targetPrice'] ?? 0).toDouble(),
      reason: data['reason'] ?? '',
      category: data['category'] ?? '단기',
      isPremium: data['isPremium'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      imageUrl: data['imageUrl'],
      currentPrice: data['currentPrice']?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'ticker': ticker,
      'name': name,
      'buyPrice': buyPrice,
      'targetPrice': targetPrice,
      'reason': reason,
      'category': category,
      'isPremium': isPremium,
      'createdAt': Timestamp.fromDate(createdAt),
      'imageUrl': imageUrl,
      'currentPrice': currentPrice,
    };
  }
}
