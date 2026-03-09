import 'package:cloud_firestore/cloud_firestore.dart';

class StockPick {
  final String id;
  final String ticker;
  final String name;
  final double buyPrice;
  final double targetPrice;
  final String reason;
  final String category; // 단기, 장기
  final String market;   // KS(KOSPI), KQ(KOSDAQ), US(미국)
  final bool isPremium;
  final DateTime createdAt;
  final String? imageUrl;
  double? currentPrice;
  final String status; // active, completed
  final double? closedPrice;
  final DateTime? closedAt;
  final int upVotes;
  final int downVotes;

  StockPick({
    required this.id,
    required this.ticker,
    required this.name,
    required this.buyPrice,
    required this.targetPrice,
    required this.reason,
    required this.category,
    this.market = 'KS',
    required this.isPremium,
    required this.createdAt,
    this.imageUrl,
    this.currentPrice,
    this.status = 'active',
    this.closedPrice,
    this.closedAt,
    this.upVotes = 0,
    this.downVotes = 0,
  });

  double get returnRate => ((targetPrice - buyPrice) / buyPrice) * 100;
  double get actualReturnRate => closedPrice != null
      ? ((closedPrice! - buyPrice) / buyPrice) * 100
      : returnRate;
  bool get isCompleted => status == 'completed';

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
      market: data['market'] ?? 'KS',
      isPremium: data['isPremium'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      imageUrl: data['imageUrl'],
      currentPrice: data['currentPrice']?.toDouble(),
      status: data['status'] ?? 'active',
      closedPrice: data['closedPrice']?.toDouble(),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      upVotes: (data['upVotes'] ?? 0).toInt(),
      downVotes: (data['downVotes'] ?? 0).toInt(),
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
      'market': market,
      'isPremium': isPremium,
      'createdAt': Timestamp.fromDate(createdAt),
      'imageUrl': imageUrl,
      'currentPrice': currentPrice,
      'status': status,
      if (closedPrice != null) 'closedPrice': closedPrice,
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    };
  }
}
