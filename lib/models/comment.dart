import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String uid;
  final String nickname;
  final String content;
  final DateTime createdAt;
  final DateTime? editedAt;

  Comment({
    required this.id,
    required this.uid,
    required this.nickname,
    required this.content,
    required this.createdAt,
    this.editedAt,
  });

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      nickname: d['nickname'] as String? ?? '익명',
      content: d['content'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'nickname': nickname,
    'content': content,
    'createdAt': Timestamp.fromDate(createdAt),
    if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
  };
}
