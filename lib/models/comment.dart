import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String uid;
  final String displayName;
  final String text;
  final DateTime createdAt;
  final String? parentId;

  const Comment({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.text,
    required this.createdAt,
    this.parentId,
  });

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      uid: data['uid'] ?? '',
      displayName: data['displayName'] ?? '익명',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      parentId: data['parentId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'displayName': displayName,
        'text': text,
        'createdAt': Timestamp.fromDate(createdAt),
        if (parentId != null) 'parentId': parentId,
      };
}
