import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/post_detail_screen.dart';
import 'firestore_service.dart';

Future<void> openSharedPost(BuildContext context, String postId) async {
  final fs = FirestoreService();
  try {
    final post = await fs.getPostOnce(postId);
    if (!context.mounted) return;
    if (post == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제되었거나 존재하지 않는 게시글입니다.')));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var liked = false;
    if (uid != null) {
      try {
        liked = await fs.hasLikedPost(post.id, uid);
      } catch (_) {
        // A failed optional lookup must not prevent reading a public post.
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          post: post,
          isOwn: uid != null && uid == post.uid,
          isLiked: liked,
          likeCount: post.likes,
          onDelete: uid != null && uid == post.uid
              ? () => fs.deletePost(post.id)
              : null,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('게시글을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.')),
    );
  }
}
