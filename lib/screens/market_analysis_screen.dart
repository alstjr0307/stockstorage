import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/market_analysis.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';

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
    ('환율(엔)', 'JPY=X'),
  ];

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;

  @override
  void initState() {
    super.initState();
    _fetchIndices();
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
    return RefreshIndicator(
      color: const Color(0xFF4ADE80),
      backgroundColor: const Color(0xFF1A2035),
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
                  color: Colors.white54,
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
                  child: const Icon(Icons.refresh,
                      color: Colors.white38, size: 16),
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
            childAspectRatio: 2.4,
            children: _indices.map((e) => _buildIndexCard(e.$1)).toList(),
          ),
          const SizedBox(height: 28),

          // ── 시황 분석 포스트 섹션 ──
          Text(
            '시황 분석',
            style: GoogleFonts.inter(
              color: Colors.white54,
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
                      style: GoogleFonts.inter(color: Colors.white38),
                    ),
                  ),
                );
              }
              return Column(
                children: list.map(_buildAnalysisCard).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndexCard(String name) {
    final result = _prices[name];
    final isUp = result?.isUp ?? true;
    final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: GoogleFonts.inter(
                color: Colors.white54,
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
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 13))
          else ...[
            Text(
              _formatValue(name, result),
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            Text(
              '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
              style: GoogleFonts.inter(
                  color: color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  String _formatValue(String name, PriceResult result) {
    if (name == 'USD/KRW' || name == '환율(엔)') {
      return '₩${NumberFormat('#,###').format(result.price.toInt())}';
    }
    if (result.isKrw) {
      return NumberFormat('#,###').format(result.price.toInt());
    }
    return NumberFormat('#,##0.00').format(result.price);
  }

  Widget _buildAnalysisCard(MarketAnalysis a) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A2035),
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
                      color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  a.title,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  a.body,
                  style: GoogleFonts.inter(
                      color: Colors.white70, fontSize: 14, height: 1.9),
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
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy.MM.dd').format(a.createdAt),
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              a.title,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              a.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: Colors.white54, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
