import 'package:cloud_firestore/cloud_firestore.dart';

class TradingJournal {
  final String id;
  final String uid;
  final String nickname;
  final String stockName;
  final String ticker;
  final String market; // KR, US, 기타
  final String action; // 매수, 매도, 기타
  final double price;
  final double quantity;
  final DateTime tradeDate;
  final String note;
  final bool isPublic;
  final int likes;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final double buyPrice;   // 매도 시 연결된 매수가 (실현손익 계산용)
  final String linkedBuyId; // 매도 시 연결된 매수 일지 ID (잔량 계산용)

  TradingJournal({
    required this.id,
    required this.uid,
    required this.nickname,
    required this.stockName,
    required this.ticker,
    required this.market,
    required this.action,
    required this.price,
    required this.quantity,
    required this.tradeDate,
    required this.note,
    required this.isPublic,
    required this.likes,
    required this.createdAt,
    this.publishedAt,
    this.buyPrice = 0,
    this.linkedBuyId = '',
  });

  factory TradingJournal.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TradingJournal(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      nickname: d['nickname'] as String? ?? '익명',
      stockName: d['stockName'] as String? ?? '',
      ticker: d['ticker'] as String? ?? '',
      market: d['market'] as String? ?? 'KR',
      action: d['action'] as String? ?? '매수',
      price: (d['price'] as num?)?.toDouble() ?? 0,
      quantity: (d['quantity'] as num?)?.toDouble() ?? 0,
      tradeDate: (d['tradeDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: d['note'] as String? ?? '',
      isPublic: d['isPublic'] as bool? ?? false,
      likes: (d['likes'] as int?) ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
      buyPrice: (d['buyPrice'] as num?)?.toDouble() ?? 0,
      linkedBuyId: d['linkedBuyId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'nickname': nickname,
        'stockName': stockName,
        'ticker': ticker,
        'market': market,
        'action': action,
        'price': price,
        'quantity': quantity,
        'tradeDate': Timestamp.fromDate(tradeDate),
        'note': note,
        'isPublic': isPublic,
        'likes': likes,
        'createdAt': Timestamp.fromDate(createdAt),
        if (publishedAt != null) 'publishedAt': Timestamp.fromDate(publishedAt!),
        if (buyPrice > 0) 'buyPrice': buyPrice,
        if (linkedBuyId.isNotEmpty) 'linkedBuyId': linkedBuyId,
      };

  TradingJournal copyWith({
    bool? isPublic,
    DateTime? publishedAt,
    double? buyPrice,
    String? linkedBuyId,
  }) => TradingJournal(
        id: id,
        uid: uid,
        nickname: nickname,
        stockName: stockName,
        ticker: ticker,
        market: market,
        action: action,
        price: price,
        quantity: quantity,
        tradeDate: tradeDate,
        note: note,
        isPublic: isPublic ?? this.isPublic,
        likes: likes,
        createdAt: createdAt,
        publishedAt: publishedAt ?? this.publishedAt,
        buyPrice: buyPrice ?? this.buyPrice,
        linkedBuyId: linkedBuyId ?? this.linkedBuyId,
      );
}
