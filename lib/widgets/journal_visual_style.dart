import 'package:flutter/material.dart';

/// Matches the existing journal and app palette; scoped to the journal only.
class JournalVisualStyle extends StatelessWidget {
  const JournalVisualStyle({super.key, required this.child});
  final Widget child;
  static const mint = Color(0xFF10B981);
  static const up = Color(0xFFF04452);
  static const down = Color(0xFF1677FF);
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF131929)
      : Colors.white;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final ink = base.colorScheme.onSurface;
    final edge = ink.withValues(alpha: .08);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: edge),
    );
    return Theme(
      data: base.copyWith(
        cardTheme: CardThemeData(
          color: surface(context),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: edge),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xFF131929) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: mint),
          ),
          hintStyle: TextStyle(color: ink.withValues(alpha: .4), fontSize: 13),
          labelStyle: TextStyle(
            color: ink.withValues(alpha: .55),
            fontSize: 13,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: mint,
            foregroundColor: const Color(0xFF06281E),
            minimumSize: const Size(0, 48),
            shape: shape,
            textStyle: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            minimumSize: const Size(0, 48),
            side: BorderSide(color: ink.withValues(alpha: .16)),
            shape: shape,
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: surface(context),
          selectedColor: mint.withValues(alpha: .14),
          side: BorderSide(color: edge),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: TextStyle(
            color: ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          showCheckmark: false,
        ),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: base.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
      child: child,
    );
  }
}

class JournalKindBadge extends StatelessWidget {
  const JournalKindBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
