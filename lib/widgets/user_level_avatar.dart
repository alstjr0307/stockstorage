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

  static const Color premiumGold = Color(0xFFE7B43E);
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

  // 프리미엄이면 레벨 써클 위에 왕관을 얹는다. 위젯 footprint는 그대로(radius*2)
  // 유지하고 왕관만 위로 살짝 넘쳐 그려 목록 레이아웃을 흔들지 않는다.
  Widget _withCrown(Widget shell, bool premium) {
    if (!premium) return shell;
    final crownW = radius * 1.05;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        shell,
        Positioned(
          top: -radius * 0.46,
          child: Transform.rotate(
            angle: -0.12,
            child: CustomPaint(
              size: Size(crownW, crownW * 0.66),
              painter: const PremiumCrownPainter(premiumGold),
            ),
          ),
        ),
      ],
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

    Widget shellForLevel(int level) {
      final accent = _levelColor(level);
      return _buildAvatarShell(
        accent: accent,
        child: Text(
          '$level',
          style: textStyle.copyWith(color: accent, fontWeight: FontWeight.w800),
        ),
      );
    }

    return StreamBuilder<({int level, bool premium})>(
      stream: _firestoreService.watchPublicUserBadge(uid),
      initialData: (level: levelOverride ?? 1, premium: false),
      builder: (context, snapshot) {
        final data = snapshot.data ?? (level: 1, premium: false);
        // 레벨은 명시 override가 있으면 우선, 없으면 공개 프로필 값.
        final level = levelOverride ?? data.level;
        return _withCrown(shellForLevel(level), data.premium);
      },
    );
  }
}

// 프리미엄 왕관 (3봉우리 + 보석 포인트). 작은 아바타~큰 프로필 모두에서 재사용.
class PremiumCrownPainter extends CustomPainter {
  const PremiumCrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(w * 0.06, h * 0.95)
      ..lineTo(0, h * 0.28)
      ..lineTo(w * 0.28, h * 0.62)
      ..lineTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.72, h * 0.62)
      ..lineTo(w, h * 0.28)
      ..lineTo(w * 0.94, h * 0.95)
      ..close();
    canvas.drawPath(path, fill);

    if (w >= 20) {
      final gem = Paint()..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(Offset(w * 0.5, h * 0.34), w * 0.05, gem);
      canvas.drawCircle(Offset(w * 0.06, h * 0.32), w * 0.04, gem);
      canvas.drawCircle(Offset(w * 0.94, h * 0.32), w * 0.04, gem);
    }
  }

  @override
  bool shouldRepaint(covariant PremiumCrownPainter oldDelegate) =>
      oldDelegate.color != color;
}
