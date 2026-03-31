import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String uid;
  final String nickname;
  final String title;
  final String content;
  final int likes;
  final DateTime createdAt;
  final List<String> imageUrls;

  Post({
    required this.id,
    required this.uid,
    required this.nickname,
    required this.title,
    required this.content,
    required this.likes,
    required this.createdAt,
    this.imageUrls = const [],
  });

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Post(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      nickname: d['nickname'] as String? ?? '익명',
      title: d['title'] as String? ?? '',
      content: d['content'] as String? ?? '',
      likes: (d['likes'] as int?) ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrls: List<String>.from(d['imageUrls'] as List? ?? []),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'nickname': nickname,
        'title': title,
        'content': content,
        'likes': likes,
        'createdAt': Timestamp.fromDate(createdAt),
        'imageUrls': imageUrls,
      };
}
