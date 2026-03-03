import 'package:cloud_firestore/cloud_firestore.dart';

class MarketAnalysis {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  const MarketAnalysis({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory MarketAnalysis.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MarketAnalysis(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'body': body,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
