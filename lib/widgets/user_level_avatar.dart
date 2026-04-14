import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class UserLevelAvatar extends StatelessWidget {
  const UserLevelAvatar({
    super.key,
    required this.uid,
    required this.radius,
    required this.backgroundColor,
    required this.textStyle,
  });

  final String uid;
  final double radius;
  final Color backgroundColor;
  final TextStyle textStyle;

  static final FirestoreService _firestoreService = FirestoreService();

  Color _levelColor(int level) {
    if (level >= 20) return const Color(0xFFDC2626);
    if (level >= 17) return const Color(0xFFEA580C);
    if (level >= 14) return const Color(0xFFF59E0B);
    if (level >= 11) return const Color(0xFF16A34A);
    if (level >= 8) return const Color(0xFF0891B2);
    if (level >= 6) return const Color(0xFF2563EB);
    if (level >= 4) return const Color(0xFF0EA5E9);
    if (level >= 3) return const Color(0xFF14B8A6);
    return const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.adminUids.contains(uid)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Color.alphaBlend(
          const Color(0xFFF59E0B).withValues(alpha: 0.22),
          backgroundColor,
        ),
        child: Icon(
          Icons.workspace_premium_rounded,
          size: radius * 1.05,
          color: const Color(0xFFF59E0B),
        ),
      );
    }

    return StreamBuilder<int>(
      stream: _firestoreService.watchPublicUserLevel(uid),
      initialData: 1,
      builder: (context, snapshot) {
        final level = snapshot.data ?? 1;
        final accent = _levelColor(level);
        return CircleAvatar(
          radius: radius,
          backgroundColor: Color.alphaBlend(
            accent.withValues(alpha: 0.22),
            backgroundColor,
          ),
          child: Text('$level', style: textStyle.copyWith(color: accent)),
        );
      },
    );
  }
}
