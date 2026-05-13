import 'package:cloud_firestore/cloud_firestore.dart';

class MarketAnalysis {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final List<String> imageUrls;

  const MarketAnalysis({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.imageUrls = const [],
  });

  factory MarketAnalysis.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MarketAnalysis(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrls: List<String>.from(data['imageUrls'] as List? ?? []),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'body': body,
    'createdAt': Timestamp.fromDate(createdAt),
    'imageUrls': imageUrls,
  };
}
