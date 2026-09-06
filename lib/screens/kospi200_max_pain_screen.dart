import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/kospi200_max_pain.dart';
import '../services/firestore_service.dart';

/// 코스피200 옵션 Max Pain 전용 상세 화면.
/// 서버가 KIS 옵션 전광판으로 계산해 캐시한 데이터를 보여준다.
class Kospi200MaxPainScreen extends StatelessWidget {
  const Kospi200MaxPainScreen({super.key});

  static const _accent = Color(0xFF10B981);
  static const _callColor = Color(0xFFF04452); // 콜=상승 베팅
  static const _putColor = Color(0xFF1677FF); // 풋=하락 베팅

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0E1A)
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '코스피200 옵션 Max Pain',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<Kospi200MaxPain?>(
        stream: FirestoreService().watchKospi200MaxPain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          final mp = snapshot.data;
          if (mp == null || mp.strikes.isEmpty) {
            return _empty(cs);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroCard(context, mp),
                const SizedBox(height: 16),
                _chartCard(context, mp),
                const SizedBox(height: 16),
                _statsRow(context, mp),
                const SizedBox(height: 20),
                _explainCard(cs),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty(ColorScheme cs) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.query_stats_rounded,
            size: 44,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            '아직 계산된 데이터가 없어요.\n장중(09:00~15:45)에 갱신됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _heroCard(BuildContext context, Kospi200MaxPain mp) {
    final cs = Theme.of(context).colorScheme;
    final ref = mp.referenceLevel;
    final pct = ref > 0 ? (mp.maxPain - ref) / ref * 100 : 0.0;
    final up = pct >= 0;
    final deltaColor = up ? _callColor : _putColor;
    final dday = mp.daysToExpiry;
    final ddayLabel = dday <= 0 ? '만기 D-day' : 'D-$dday';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.14),
            _accent.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(color: _accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Max Pain',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$ddayLabel · ${_fmtDate(mp.expiryDate)} 만기',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                mp.maxPain.toStringAsFixed(2),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '현재 ${ref.toStringAsFixed(1)} 대비 ${up ? '↑' : '↓'}${pct.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: deltaColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartCard(BuildContext context, Kospi200MaxPain mp) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '행사가별 미결제약정',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _Kospi200OiPainter(
                strikes: mp.strikes,
                maxPain: mp.maxPain,
                reference: mp.referenceLevel,
                callColor: _callColor,
                putColor: _putColor,
                maxPainColor: _accent,
                axisColor: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legend('콜 OI', _callColor, cs),
              const SizedBox(width: 14),
              _legend('풋 OI', _putColor, cs),
              const SizedBox(width: 14),
              _legend('Max Pain', _accent, cs),
              const Spacer(),
              Text(
                '현재 ${mp.referenceLevel.toStringAsFixed(1)}',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsRow(BuildContext context, Kospi200MaxPain mp) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _stat(cs, '콜 OI 합', _fmtInt(mp.totalCallOi), _callColor),
        const SizedBox(width: 10),
        _stat(cs, '풋 OI 합', _fmtInt(mp.totalPutOi), _putColor),
        const SizedBox(width: 10),
        _stat(
          cs,
          'P/C Ratio',
          mp.putCallRatio?.toStringAsFixed(2) ?? '-',
          cs.onSurface,
        ),
      ],
    );
  }

  Widget _stat(ColorScheme cs, String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _explainCard(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                'Max Pain이란?',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '옵션 만기일에 옵션 매수자 전체의 손실이 최대가 되는(=매도자 이익이 최대가 되는) '
            '코스피200 지수 레벨입니다. 만기일에 지수가 이 근처로 수렴하려는 경향이 있다는 '
            '이론이 있으나 통계적 경향일 뿐이며, 최근월 옵션 미결제약정(OI) 기준으로 '
            '장중 갱신됩니다. 투자 판단의 참고 지표로만 활용하세요.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 12.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(String ymd) {
    final d = DateTime.tryParse(ymd);
    return d == null ? ymd : DateFormat('M/d').format(d);
  }

  static String _fmtInt(int v) => NumberFormat('#,###').format(v);
}

/// 행사가별 콜/풋 OI 바 차트 + Max Pain·현재가 마커.
/// 데이터가 많아 현재가(reference) 중심 ±window 범위만 그린다.
class _Kospi200OiPainter extends CustomPainter {
  final List<Kospi200OiStrike> strikes;
  final double maxPain;
  final double reference;
  final Color callColor;
  final Color putColor;
  final Color maxPainColor;
  final Color axisColor;

  _Kospi200OiPainter({
    required this.strikes,
    required this.maxPain,
    required this.reference,
    required this.callColor,
    required this.putColor,
    required this.maxPainColor,
    required this.axisColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strikes.isEmpty) return;

    // 현재가 기준 ±12% 범위만 표시 (가독성). 너무 좁으면 전체.
    final lo = reference * 0.88;
    final hi = reference * 1.12;
    var visible = strikes
        .where((s) => s.strike >= lo && s.strike <= hi)
        .toList();
    if (visible.length < 6) visible = List.of(strikes);
    visible.sort((a, b) => a.strike.compareTo(b.strike));
    if (visible.isEmpty) return;

    final maxOi = visible
        .map((s) => max(s.callOi, s.putOi))
        .fold<int>(0, max)
        .toDouble();
    if (maxOi <= 0) return;

    const labelH = 16.0;
    final chartH = size.height - labelH;
    final slotW = size.width / visible.length;
    final barW = max(1.0, slotW * 0.36);

    final callPaint = Paint()..color = callColor.withValues(alpha: 0.8);
    final putPaint = Paint()..color = putColor.withValues(alpha: 0.8);

    for (var i = 0; i < visible.length; i++) {
      final s = visible[i];
      final cx = slotW * (i + 0.5);
      final callH = chartH * (s.callOi / maxOi);
      if (callH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW, chartH - callH, barW, callH),
            const Radius.circular(1),
          ),
          callPaint,
        );
      }
      final putH = chartH * (s.putOi / maxOi);
      if (putH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx, chartH - putH, barW, putH),
            const Radius.circular(1),
          ),
          putPaint,
        );
      }
    }

    double xForLevel(double level) {
      for (var i = 0; i < visible.length; i++) {
        if (visible[i].strike >= level) {
          if (i == 0) return slotW * 0.5;
          final prev = visible[i - 1].strike;
          final next = visible[i].strike;
          final t = next > prev ? (level - prev) / (next - prev) : 0.0;
          return slotW * (i - 0.5 + t);
        }
      }
      return size.width - slotW * 0.5;
    }

    // Max Pain 세로선
    final mpX = xForLevel(maxPain);
    canvas.drawLine(
      Offset(mpX, 0),
      Offset(mpX, chartH),
      Paint()
        ..color = maxPainColor
        ..strokeWidth = 1.8,
    );

    // 현재가(ATM) 점선
    final refX = xForLevel(reference);
    final dashPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;
    for (double y = 0; y < chartH; y += 8) {
      canvas.drawLine(
        Offset(refX, y),
        Offset(refX, min(y + 4, chartH)),
        dashPaint,
      );
    }

    // X축 라벨
    void drawLabel(String text, double x, TextAlign align) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: axisColor, fontSize: 9),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      double dx = switch (align) {
        TextAlign.left => x,
        TextAlign.right => x - tp.width,
        _ => x - tp.width / 2,
      };
      dx = dx.clamp(0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, chartH + 3));
    }

    drawLabel('MP ${maxPain.toStringAsFixed(0)}', mpX, TextAlign.center);
    drawLabel(visible.first.strike.toStringAsFixed(0), 0, TextAlign.left);
    drawLabel(
      visible.last.strike.toStringAsFixed(0),
      size.width,
      TextAlign.right,
    );
  }

  @override
  bool shouldRepaint(covariant _Kospi200OiPainter old) =>
      old.strikes != strikes ||
      old.maxPain != maxPain ||
      old.reference != reference;
}
