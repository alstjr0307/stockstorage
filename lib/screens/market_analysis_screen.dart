import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/market_analysis.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'index_detail_screen.dart';

class MarketAnalysisScreen extends StatefulWidget {
  const MarketAnalysisScreen({super.key});

  @override
  State<MarketAnalysisScreen> createState() => _MarketAnalysisScreenState();
}

class _MarketAnalysisScreenState extends State<MarketAnalysisScreen> {
  static const _indices = [
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('S&P 500', '^GSPC'),
    ('NASDAQ', '^IXIC'),
    ('USD/KRW', 'KRW=X'),
    ('나스닥100 선물', 'NQ=F'),
  ];

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;

  // 실적 캘린더
  List<({StockPick pick, DateTime earningsDate})> _earnings = [];
  bool _loadingEarnings = true;

  @override
  void initState() {
    super.initState();
    _fetchIndices();
    _fetchEarnings();
  }

  Future<void> _fetchEarnings() async {
    final picks = await FirestoreService().getRecentActivePicks();
    final usPicks = picks.where((p) => p.market == 'US').toList();
    final futures = usPicks.map((p) => StockPriceService.fetchEarningsDate(p.ticker, p.market));
    final dates = await Future.wait(futures);
    final now = DateTime.now();
    final result = <({StockPick pick, DateTime earningsDate})>[];
    for (var i = 0; i < usPicks.length; i++) {
      final d = dates[i];
      if (d != null && d.isAfter(now.subtract(const Duration(days: 1)))) {
        result.add((pick: usPicks[i], earningsDate: d));
      }
    }
    result.sort((a, b) => a.earningsDate.compareTo(b.earningsDate));
    if (mounted) setState(() { _earnings = result; _loadingEarnings = false; });
  }

  Future<void> _fetchIndices() async {
    setState(() => _loadingIndices = true);
    final results = await Future.wait(
      _indices.map((e) => StockPriceService.fetchPrice(e.$2, 'US')),
    );
    if (mounted) {
      setState(() {
        for (var i = 0; i < _indices.length; i++) {
          _prices[_indices[i].$1] = results[i];
        }
        _loadingIndices = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: const Color(0xFF4ADE80),
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _fetchIndices,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── 주요 지수 섹션 ──
          Row(
            children: [
              Text(
                '주요 지수',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_loadingIndices)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF4ADE80)),
                )
              else
                GestureDetector(
                  onTap: _fetchIndices,
                  child: Icon(Icons.refresh,
                      color: cs.onSurface.withValues(alpha: 0.38), size: 16),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: _indices.map((e) => _buildIndexCard(context, e.$1)).toList(),
          ),
          const SizedBox(height: 28),

          // ── 실적 캘린더 섹션 ──
          Text(
            '실적 발표 일정 (US)',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.54),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingEarnings)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80))),
            )
          else if (_earnings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('예정된 실적 발표가 없습니다',
                  style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 13)),
            )
          else
            ...(_earnings.map((e) {
              final daysLeft = e.earningsDate.difference(DateTime.now()).inDays;
              final label = daysLeft == 0 ? '오늘' : 'D-$daysLeft';
              final urgent = daysLeft <= 3;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.pick.name,
                              style: GoogleFonts.inter(
                                  color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(e.pick.ticker,
                              style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(DateFormat('MM/dd').format(e.earningsDate),
                            style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.54), fontSize: 12)),
                        Text(label,
                            style: GoogleFonts.inter(
                                color: urgent ? Colors.orangeAccent : const Color(0xFF4ADE80),
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              );
            })),
          const SizedBox(height: 20),

          // ── 시황 분석 포스트 섹션 ──
          Text(
            '시황 분석',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.54),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<MarketAnalysis>>(
            stream: FirestoreService().getMarketAnalyses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4ADE80))),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '등록된 시황 분석이 없습니다',
                      style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38)),
                    ),
                  ),
                );
              }
              return Column(
                children: list.map((a) => _buildAnalysisCard(context, a)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndexCard(BuildContext context, String name) {
    final entry = _indices.firstWhere((e) => e.$1 == name);
    final result = _prices[name];
    final isUp = result?.isUp ?? true;
    final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IndexDetailScreen(
            name: name,
            symbol: entry.$2,
            initialPrice: result,
          ),
        ),
      ),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          if (_loadingIndices)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF4ADE80)),
            )
          else if (result == null)
            Text('--',
                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 13))
          else ...[
            Text(
              _formatValue(name, result),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            Text(
              '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
      ),
    );
  }

  String _formatValue(String name, PriceResult result) {
    if (name == 'USD/KRW') {
      return '₩${NumberFormat('#,###').format(result.price.toInt())}';
    }
    if (result.isKrw) {
      return NumberFormat('#,###').format(result.price.toInt());
    }
    return NumberFormat('#,##0.00').format(result.price);
  }

  Widget _buildAnalysisCard(BuildContext context, MarketAnalysis a) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('yyyy년 MM월 dd일').format(a.createdAt),
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.38), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  a.title,
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  a.body,
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.7), fontSize: 14, height: 1.9),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy.MM.dd').format(a.createdAt),
              style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              a.title,
              style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              a.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.54), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
