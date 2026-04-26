import 'package:cloud_firestore/cloud_firestore.dart';

class FmkoreaStockMention {
  const FmkoreaStockMention({
    required this.ticker,
    required this.name,
    required this.mentionCount,
    required this.postCount,
  });

  final String ticker;
  final String name;
  final int mentionCount;
  final int postCount;

  factory FmkoreaStockMention.fromMap(Map<String, dynamic> map) {
    return FmkoreaStockMention(
      ticker: map['ticker'] as String? ?? '',
      name: map['name'] as String? ?? '',
      mentionCount: (map['mentionCount'] as num?)?.toInt() ?? 0,
      postCount: (map['postCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class FmkoreaStockMentionsSnapshot {
  const FmkoreaStockMentionsSnapshot({
    required this.id,
    required this.dateKey,
    required this.totalPosts,
    required this.matchedPostCount,
    required this.uniqueStockCount,
    required this.topMentions,
    required this.mode,
    required this.updatedAt,
  });

  final String id;
  final String dateKey;
  final int totalPosts;
  final int matchedPostCount;
  final int uniqueStockCount;
  final List<FmkoreaStockMention> topMentions;
  final String mode;
  final DateTime? updatedAt;

  factory FmkoreaStockMentionsSnapshot.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final mentionsRaw = data['topMentions'] as List<dynamic>? ?? const [];
    return FmkoreaStockMentionsSnapshot(
      id: doc.id,
      dateKey: data['dateKey'] as String? ?? '',
      totalPosts: (data['totalPosts'] as num?)?.toInt() ?? 0,
      matchedPostCount: (data['matchedPostCount'] as num?)?.toInt() ?? 0,
      uniqueStockCount: (data['uniqueStockCount'] as num?)?.toInt() ?? 0,
      topMentions: mentionsRaw
          .whereType<Map>()
          .map(
            (item) =>
                FmkoreaStockMention.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      mode: data['mode'] as String? ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
