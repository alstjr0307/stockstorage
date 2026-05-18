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
    this.levelOverride,
  });

  final String uid;
  final double radius;
  final Color backgroundColor;
  final TextStyle textStyle;
  final int? levelOverride;

  static final FirestoreService _firestoreService = FirestoreService();

  Widget _buildAvatarShell({required Color accent, required Widget child}) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(accent.withValues(alpha: 0.2), backgroundColor),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.1),
      ),
      child: Center(child: child),
    );
  }

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
      const adminAccent = Color(0xFFF59E0B);
      return _buildAvatarShell(
        accent: adminAccent,
        child: Icon(
          Icons.workspace_premium_rounded,
          size: radius * 0.9,
          color: adminAccent,
        ),
      );
    }

    final fixedLevel = levelOverride;
    if (fixedLevel != null) {
      final accent = _levelColor(fixedLevel);
      return _buildAvatarShell(
        accent: accent,
        child: Text(
          '$fixedLevel',
          style: textStyle.copyWith(color: accent, fontWeight: FontWeight.w800),
        ),
      );
    }

    return StreamBuilder<int>(
      stream: _firestoreService.watchPublicUserLevel(uid),
      initialData: 1,
      builder: (context, snapshot) {
        final level = snapshot.data ?? 1;
        final accent = _levelColor(level);
        return _buildAvatarShell(
          accent: accent,
          child: Text(
            '$level',
            style: textStyle.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}
