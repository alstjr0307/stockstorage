import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stock_pick.dart';
import '../services/stock_price_service.dart';

class StockAiAnalysisResultScreen extends StatelessWidget {
  final StockPick pick;
  final StockAiAnalysisResult analysis;
  final PriceResult? price;
  final FundamentalsResult? fundamentals;

  const StockAiAnalysisResultScreen({
    super.key,
    required this.pick,
    required this.analysis,
    this.price,
    this.fundamentals,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = analysis.score;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AI 종목 분석',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _HeaderCard(
              pick: pick,
              score: score,
              scoreLabel: analysis.scoreLabel,
              price: price,
            ),
            const SizedBox(height: 12),
            _SummaryCard(text: _cleanSummaryText(analysis.summary)),
            const SizedBox(height: 12),
            _MetricStrip(fundamentals: fundamentals),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.category_outlined,
              title: '테마 / 섹터',
              body: _joinText([analysis.theme, analysis.sector]),
              color: const Color(0xFF10B981),
            ),
            _SectionCard(
              icon: Icons.trending_up,
              title: '당일 등락 이유',
              body: analysis.todayReason,
              color: const Color(0xFFF59E0B),
            ),
            _SectionCard(
              icon: Icons.account_balance_outlined,
              title: '실적 / 밸류에이션',
              body: analysis.fundamentals,
              color: const Color(0xFF6366F1),
            ),
            _SectionCard(
              icon: Icons.candlestick_chart_outlined,
              title: '기술적 분석',
              body: analysis.technical,
              color: const Color(0xFF1677FF),
            ),
            _SectionCard(
              icon: Icons.article_outlined,
              title: '뉴스 분석',
              body: analysis.news,
              color: const Color(0xFF14B8A6),
            ),
            _SectionCard(
              icon: Icons.bolt_outlined,
              title: '모멘텀',
              body: analysis.momentum,
              color: const Color(0xFFF04452),
            ),
            if (analysis.risks.isNotEmpty) _RiskCard(risks: analysis.risks),
            for (final section in analysis.sections)
              _SectionCard(
                icon: Icons.checklist_outlined,
                title: section.title,
                body: section.body,
                color: const Color(0xFF64748B),
              ),
            const SizedBox(height: 6),
            Text(
              'AI 분석은 학습과 참고용입니다. 투자 판단과 결과에 대한 책임은 본인에게 있습니다.',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.36),
                fontSize: 11,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _joinText(List<String> values) {
    return values.map(_cleanText).where((v) => v.isNotEmpty).join('\n\n');
  }

  static String _cleanText(String value) {
    var text = value.trim();
    text = text.replaceAll(
      RegExp(
        r'^\s*"(summary|theme|sector|todayReason|fundamentals|technical|news|momentum)"\s*:\s*"?',
      ),
      '',
    );
    text = text.replaceAll(RegExp(r'",?\s*$'), '');
    text = text.replaceAll(RegExp(r'^\s*[-•]\s*'), '');
    return text.trim();
  }

  static String _cleanSummaryText(String value) {
    var text = _cleanText(value);
    final match = RegExp(
      r',?\s*"(theme|sector|todayReason|fundamentals|technical|news|momentum|risks|sections)"\s*:',
    ).firstMatch(text);
    if (match != null && match.start > 0) {
      text = text.substring(0, match.start);
    }
    return _cleanText(text);
  }
}

class _HeaderCard extends StatelessWidget {
  final StockPick pick;
  final double? score;
  final String scoreLabel;
  final PriceResult? price;

  const _HeaderCard({
    required this.pick,
    required this.score,
    required this.scoreLabel,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scoreValue = score?.round();
    final scoreColor = _scoreColor(score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pick.name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _MarketPill(market: pick.market),
                        const SizedBox(width: 8),
                        Text(
                          pick.ticker,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scoreColor.withValues(alpha: 0.34),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  scoreValue == null ? '--' : '$scoreValue',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: score == null ? 0 : (score!.clamp(0, 100) / 100),
              minHeight: 8,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              color: scoreColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  scoreLabel.isEmpty ? '점수는 참고용 종합 평가입니다.' : scoreLabel,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (price != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price!.formattedPrice,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      price!.formattedChange,
                      style: TextStyle(
                        color: price!.isUp
                            ? const Color(0xFFF04452)
                            : const Color(0xFF1677FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String text;

  const _SummaryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.auto_awesome,
            title: '핵심 요약',
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.78),
              fontSize: 14,
              height: 1.65,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final FundamentalsResult? fundamentals;

  const _MetricStrip({required this.fundamentals});

  @override
  Widget build(BuildContext context) {
    final f = fundamentals;
    if (f == null ||
        (f.marketCap == null &&
            f.per == null &&
            f.pbr == null &&
            f.bps == null)) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (f.marketCap != null)
          _MetricChip(label: '시총', value: _formatMarketCap(f.marketCap!)),
        if (f.per != null)
          _MetricChip(label: 'PER', value: f.per!.toStringAsFixed(1)),
        if (f.pbr != null)
          _MetricChip(label: 'PBR', value: f.pbr!.toStringAsFixed(2)),
        if (f.bps != null)
          _MetricChip(label: 'BPS', value: NumberFormat('#,###').format(f.bps)),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.42),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cleaned = StockAiAnalysisResultScreen._cleanText(body);
    if (cleaned.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(cs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(icon: icon, title: title, color: color),
            const SizedBox(height: 10),
            Text(
              cleaned,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.70),
                fontSize: 13,
                height: 1.65,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final List<String> risks;

  const _RiskCard({required this.risks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cleaned = risks
        .map(StockAiAnalysisResultScreen._cleanText)
        .where((v) => v.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(cs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              icon: Icons.warning_amber_rounded,
              title: '리스크',
              color: const Color(0xFFF04452),
            ),
            const SizedBox(height: 10),
            ...cleaned.map(
              (risk) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 8, right: 9),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF04452),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        risk,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.70),
                          fontSize: 13,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _CardTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _MarketPill extends StatelessWidget {
  final String market;

  const _MarketPill({required this.market});

  @override
  Widget build(BuildContext context) {
    final info = switch (market) {
      'KS' => ('KOSPI', const Color(0xFF3182F6)),
      'KQ' => ('KOSDAQ', const Color(0xFF00C4B4)),
      _ => ('US', const Color(0xFFF59E0B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        info.$1,
        style: TextStyle(
          color: info.$2,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(ColorScheme cs) {
  return BoxDecoration(
    color: cs.surface.withValues(alpha: 0.96),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

Color _scoreColor(double? score) {
  if (score == null) return const Color(0xFF10B981);
  if (score >= 70) return const Color(0xFFF04452);
  if (score >= 45) return const Color(0xFFF59E0B);
  return const Color(0xFF1677FF);
}

String _formatMarketCap(int value) {
  if (value >= 1000000000000) {
    return '${(value / 1000000000000).toStringAsFixed(1)}조';
  }
  if (value >= 100000000) {
    return '${(value / 100000000).round()}억';
  }
  return NumberFormat('#,###').format(value);
}
