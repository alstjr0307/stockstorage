import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/market_analysis.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'index_detail_screen.dart';
import 'market_analysis_detail_screen.dart';
import 'market_sentiment_screen.dart';

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

  static const _indexDescriptions = {
    'KOSPI': '한국 대형주 종합지수',
    'KOSDAQ': '한국 성장주 중심 시장',
    'S&P 500': '미국 대표 500대 기업',
    'NASDAQ': '미국 기술주 중심 지수',
    'USD/KRW': '원달러 환율',
    '나스닥100 선물': '미국 장전 분위기',
  };

  static const _indexAccentColors = {
    'KOSPI': Color(0xFF22C55E),
    'KOSDAQ': Color(0xFF10B981),
    'S&P 500': Color(0xFF3B82F6),
    'NASDAQ': Color(0xFF6366F1),
    'USD/KRW': Color(0xFFF59E0B),
    '나스닥100 선물': Color(0xFFF97316),
  };

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;
  int _indicesRequestSerial = 0;
  DateTime? _indicesFetchedAt;

  @override
  void initState() {
    super.initState();
    _fetchIndices();
  }

  Future<void> _fetchIndices({bool forceRefresh = false}) async {
    final requestSerial = ++_indicesRequestSerial;
    if (mounted) {
      setState(() => _loadingIndices = true);
    }

    if (forceRefresh) {
      for (final entry in _indices) {
        StockPriceService.invalidateCache(entry.$2);
      }
    }

    final results = await Future.wait(
      _indices.map((entry) => StockPriceService.fetchPrice(entry.$2, 'US')),
    );

    if (!mounted || requestSerial != _indicesRequestSerial) {
      return;
    }

    setState(() {
      for (var i = 0; i < _indices.length; i++) {
        _prices[_indices[i].$1] = results[i];
      }
      _loadingIndices = false;
      _indicesFetchedAt = DateTime.now();
    });
  }

  Future<void> _refreshAll() async {
    await _fetchIndices(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: _buildTopTabBar(context),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _buildIndicatorsTab(context),
                _buildAnalysisTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: isDark ? 0.88 : 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.zero,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: const Color(0xFF4ADE80),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(15),
        labelColor: Colors.black,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.56),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        tabs: const [
          SizedBox(
            height: 48,
            child: Tab(text: '지표'),
          ),
          SizedBox(
            height: 48,
            child: Tab(text: '시황분석'),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorsTab(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF4ADE80),
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
        children: [
          _buildIndicesPanel(context),
          const SizedBox(height: 18),
          _buildIndicatorShortcuts(context),
        ],
      ),
    );
  }

  Widget _buildIndicatorShortcuts(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '세부 지표',
            style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '필요한 지표만 눌러서 상세 화면으로 바로 들어갈 수 있어요.',
            style: GoogleFonts.inter(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.52),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.86,
          children: [
            _IndicatorShortcutCard(
              title: '마감수급',
              subtitle: '수급 TOP5',
              icon: Icons.candlestick_chart_rounded,
              accent: const Color(0xFFF59E0B),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _InvestorFlowDetailScreen(),
                  ),
                );
              },
            ),
            _IndicatorShortcutCard(
              title: '시장 심리\n지표',
              subtitle: '공포/탐욕',
              icon: Icons.psychology_alt_rounded,
              accent: const Color(0xFF22C55E),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MarketSentimentScreen(),
                  ),
                );
              },
            ),
            _IndicatorShortcutCard(
              title: '펨코지수',
              subtitle: '커뮤니티 흐름',
              icon: Icons.forum_rounded,
              accent: const Color(0xFF3B82F6),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _FmkoreaIndexDetailScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSentimentEntryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF14532D)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '시장 심리 지표',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '공포탐욕지수와 주요 심리 지표를 한 화면에서 확인하세요.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '시장 온도, 금리, 변동성 흐름까지 따로 정리한 전용 화면으로 이동합니다.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MarketSentimentScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4ADE80),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: Text(
                '시장 심리 지표 보러가기',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicesPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
                      '주요 지수',
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _indicesFetchedAt == null
                          ? '핵심 시장 지수를 빠르게 확인하세요'
                          : '기준 시간 ${DateFormat('오늘 HH:mm').format(_indicesFetchedAt!)}',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loadingIndices)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4ADE80),
                  ),
                )
              else
                IconButton(
                  onPressed: () => _fetchIndices(forceRefresh: true),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: cs.onSurface.withValues(alpha: 0.46),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _indices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.06,
            ),
            itemBuilder: (context, index) {
              return _buildIndexCard(
                context,
                _indices[index].$1,
                _indices[index].$2,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIndexCard(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _prices[name];
    final accent = _indexAccentColors[name] ?? const Color(0xFF4ADE80);
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndexDetailScreen(
              name: name,
              symbol: symbol,
              initialPrice: result,
            ),
          ),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.26 : 0.18),
            width: 1.1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: isDark ? 0.18 : 0.16),
              cs.surface,
              cs.surface,
            ],
            stops: const [0, 0.22, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: isDark ? 0.10 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.trending_up_rounded,
                      size: 15,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _indexDescriptions[name] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.44),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_loadingIndices && result == null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4ADE80),
                  ),
                )
              else if (result == null)
                Text(
                  '--',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.36),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else ...[
                Text(
                  _displayValue(name, result),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: moveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      color: moveColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _displayValue(String name, PriceResult result) {
    if (name == 'USD/KRW') {
      return '₩${NumberFormat('#,###').format(result.price.toInt())}';
    }
    if (result.isKrw) {
      return NumberFormat('#,###').format(result.price.toInt());
    }
    return NumberFormat('#,##0.00').format(result.price);
  }

  Widget _buildAnalysisTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<MarketAnalysis>>(
      stream: FirestoreService().getMarketAnalyses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF4ADE80)),
          );
        }

        final list = snapshot.data ?? [];
        final latestDate = list.isEmpty
            ? null
            : list
                .map((item) => item.createdAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF4ADE80).withValues(alpha: 0.08),
                    cs.surface,
                  ],
                ),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'DAILY BRIEF',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF15803D),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _buildAnalysisSummaryChip(
                        context,
                        icon: Icons.feed_outlined,
                        label: '${list.length}개 글',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '시황분석',
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '매일 업데이트되는 시황 분석 글을 카드형으로 정리했습니다. 글을 누르면 상세 페이지에서 편하게 읽을 수 있습니다.',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                  if (latestDate != null) ...[
                    const SizedBox(height: 14),
                    _buildAnalysisSummaryChip(
                      context,
                      icon: Icons.schedule_rounded,
                      label:
                          '최신 업데이트 ${DateFormat('MM.dd HH:mm').format(latestDate)}',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (list.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.05),
                  ),
                ),
                child: Center(
                  child: Text(
                    '등록된 시황 분석이 없습니다.',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.42),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              ...list.map((analysis) => _buildAnalysisCard(context, analysis)),
          ],
        );
      },
    );
  }

  Widget _buildAnalysisCard(BuildContext context, MarketAnalysis analysis) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = analysis.imageUrls.isNotEmpty;
    final preview = analysis.body.replaceAll('\n', ' ').trim();
    final accent = hasImage
        ? const Color(0xFF3B82F6)
        : const Color(0xFF16A34A);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MarketAnalysisDetailScreen(analysis: analysis),
              ),
            );
          },
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF4ADE80,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          DateFormat('yyyy.MM.dd').format(analysis.createdAt),
                          style: GoogleFonts.inter(
                            color: const Color(0xFF15803D),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        analysis.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        preview.isEmpty ? '본문이 없습니다.' : preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.58),
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              hasImage ? '이미지 포함' : '텍스트 중심',
                              style: GoogleFonts.inter(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '자세히 보기',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.52),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.16),
                        accent.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                  child: Icon(
                    hasImage ? Icons.article_outlined : Icons.subject_rounded,
                    color: accent.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisSummaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: cs.onSurface.withValues(alpha: 0.52),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.64),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvestorFlowCard extends StatelessWidget {
  const _InvestorFlowCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('market_investor_flow')
          .orderBy('marketDate', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: _buildBody(context, snapshot),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    final cs = Theme.of(context).colorScheme;

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF4ADE80),
          ),
        ),
      );
    }

    if (snapshot.hasError) {
      return _buildMessage(context, '수급 데이터를 불러오지 못했습니다.');
    }

    final doc = snapshot.data?.docs.isNotEmpty == true
        ? snapshot.data!.docs.first
        : null;
    if (doc == null) {
      return _buildMessage(context, '아직 수급 데이터가 없습니다.');
    }

    final data = _InvestorFlowSnapshot.fromMap(doc.data());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '마감 수급 TOP5',
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                data.marketDate,
                style: GoogleFonts.inter(
                  color: const Color(0xFFB45309),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '코스피와 코스닥에서 외국인과 기관이 많이 담은 종목을 마감 기준으로 정리했습니다.',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.54),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _InvestorFlowMarketBlock(
          marketLabel: 'KOSPI',
          foreignTop5: data.kospiForeignTop5,
          institutionTop5: data.kospiInstitutionTop5,
        ),
        const SizedBox(height: 12),
        _InvestorFlowMarketBlock(
          marketLabel: 'KOSDAQ',
          foreignTop5: data.kosdaqForeignTop5,
          institutionTop5: data.kosdaqInstitutionTop5,
        ),
      ],
    );
  }

  Widget _buildMessage(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 92,
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.42),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IndicatorShortcutCard extends StatelessWidget {
  const _IndicatorShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.28 : 0.18),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.18 : 0.14),
                cs.surface,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.12 : 0.10),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.52),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IndicatorDetailScaffold extends StatelessWidget {
  const _IndicatorDetailScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [child],
        ),
      ),
    );
  }
}

class _InvestorFlowDetailScreen extends StatelessWidget {
  const _InvestorFlowDetailScreen();

  @override
  Widget build(BuildContext context) {
    return const _IndicatorDetailScaffold(
      title: '마감수급',
      subtitle: '외국인과 기관 매매 상위 종목',
      child: _InvestorFlowCard(),
    );
  }
}

class _FmkoreaIndexDetailScreen extends StatelessWidget {
  const _FmkoreaIndexDetailScreen();

  @override
  Widget build(BuildContext context) {
    return const _IndicatorDetailScaffold(
      title: '펨코지수',
      subtitle: '게시글 수와 KOSPI 흐름 비교',
      child: _FmkoreaIndexCard(),
    );
  }
}

class _InvestorFlowMarketBlock extends StatelessWidget {
  const _InvestorFlowMarketBlock({
    required this.marketLabel,
    required this.foreignTop5,
    required this.institutionTop5,
  });

  final String marketLabel;
  final List<_InvestorFlowItem> foreignTop5;
  final List<_InvestorFlowItem> institutionTop5;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            marketLabel,
            style: GoogleFonts.inter(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _InvestorFlowGroup(
            title: '외국인 순매수',
            color: const Color(0xFF22C55E),
            items: foreignTop5,
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(height: 10),
          _InvestorFlowGroup(
            title: '기관 순매수',
            color: const Color(0xFFF97316),
            items: institutionTop5,
            icon: Icons.account_balance_rounded,
          ),
        ],
      ),
    );
  }
}

class _InvestorFlowGroup extends StatelessWidget {
  const _InvestorFlowGroup({
    required this.title,
    required this.color,
    required this.items,
    required this.icon,
  });

  final String title;
  final Color color;
  final List<_InvestorFlowItem> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.13), cs.surface],
        ),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '순매수 금액 기준 상위 5개',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.42),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              '데이터가 없습니다.',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.42),
                fontSize: 12,
              ),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.rank}',
                        style: GoogleFonts.inter(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.amountEokText,
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface.withValues(alpha: 0.74),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InvestorFlowSnapshot {
  const _InvestorFlowSnapshot({
    required this.marketDate,
    required this.kospiForeignTop5,
    required this.kospiInstitutionTop5,
    required this.kosdaqForeignTop5,
    required this.kosdaqInstitutionTop5,
  });

  final String marketDate;
  final List<_InvestorFlowItem> kospiForeignTop5;
  final List<_InvestorFlowItem> kospiInstitutionTop5;
  final List<_InvestorFlowItem> kosdaqForeignTop5;
  final List<_InvestorFlowItem> kosdaqInstitutionTop5;

  factory _InvestorFlowSnapshot.fromMap(Map<String, dynamic> map) {
    final kospi = Map<String, dynamic>.from((map['kospi'] as Map?) ?? const {});
    final kosdaq = Map<String, dynamic>.from(
      (map['kosdaq'] as Map?) ?? const {},
    );
    return _InvestorFlowSnapshot(
      marketDate: (map['marketDate'] as String?) ?? '-',
      kospiForeignTop5: _parseInvestorFlowItems(kospi['foreignTop5']),
      kospiInstitutionTop5: _parseInvestorFlowItems(kospi['institutionTop5']),
      kosdaqForeignTop5: _parseInvestorFlowItems(kosdaq['foreignTop5']),
      kosdaqInstitutionTop5: _parseInvestorFlowItems(kosdaq['institutionTop5']),
    );
  }
}

class _InvestorFlowItem {
  const _InvestorFlowItem({
    required this.rank,
    required this.name,
    required this.amount,
  });

  final int rank;
  final String name;
  final num? amount;

  String get amountEokText {
    if (amount == null) return '-';
    final eok = amount! / 100;
    return eok >= 100
        ? '${eok.toStringAsFixed(0)}억'
        : '${eok.toStringAsFixed(1)}억';
  }

  factory _InvestorFlowItem.fromMap(Map<String, dynamic> map) {
    return _InvestorFlowItem(
      rank: (map['rank'] as num?)?.toInt() ?? 0,
      name: (map['name'] as String?) ?? '-',
      amount: map['amount'] as num?,
    );
  }
}

List<_InvestorFlowItem> _parseInvestorFlowItems(Object? raw) {
  final list = raw as List<dynamic>? ?? const [];
  return list
      .whereType<Map>()
      .map((item) => _InvestorFlowItem.fromMap(Map<String, dynamic>.from(item)))
      .toList();
}

class _FmkoreaIndexCard extends StatelessWidget {
  const _FmkoreaIndexCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fmkorea_index')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 180,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF4ADE80)),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildFmkoreaMessage(context, '펨코 지수를 불러오지 못했습니다.');
        }

        final entries =
            snapshot.data?.docs
                .map(
                  (doc) => _FmkoreaDailyCount(
                    dateKey: doc.id,
                    count: (doc.data()['count'] as num?)?.toInt() ?? 0,
                    updatedAt: (doc.data()['updatedAt'] as Timestamp?)
                        ?.toDate(),
                  ),
                )
                .toList() ??
            [];

        entries.sort((a, b) => a.dateKey.compareTo(b.dateKey));

        if (entries.isEmpty) {
          return _buildFmkoreaMessage(context, '표시할 데이터가 없습니다.');
        }

        final latest = entries.last;
        final chartEntries = entries.length > 14
            ? entries.sublist(entries.length - 14)
            : entries;
        final maxCount = chartEntries
            .map((entry) => entry.count)
            .fold<int>(1, (acc, value) => value > acc ? value : acc);
        final updatedAt = entries
            .map((entry) => entry.updatedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (acc, item) {
              if (acc == null) return item;
              return item.isAfter(acc) ? item : acc;
            });
        final weekdayInsight = _computeWeekdayInsight(entries);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('fmkorea_index_meta')
              .doc('summary')
              .snapshots(),
          builder: (context, summarySnapshot) {
            final summaryData = summarySnapshot.data?.data();
            final storedSummary = summaryData == null
                ? null
                : _FmkoreaStoredSummary.fromMap(summaryData);

            return FutureBuilder<_FmkoreaKospiCorrelation?>(
              future: storedSummary == null
                  ? _computeKospiCorrelation(entries)
                  : Future.value(storedSummary.correlation),
              builder: (context, corrSnapshot) {
                final correlation = corrSnapshot.data;
                final effectiveInsight =
                    storedSummary?.weekdayInsight ?? weekdayInsight;
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '펨코 지수',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '일간 게시글',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF15803D),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '오늘 수치 자체보다, 주말 제외 평일 평균 대비 얼마나 높은지가 더 중요합니다.',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.54),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4ADE80).withValues(alpha: 0.14),
                          cs.surface,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${latest.dateKey} 게시글 수',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${latest.count}',
                              style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '건',
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (effectiveInsight == null)
                          Text(
                            '평일 평균을 내기에는 아직 데이터가 부족합니다.',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.56),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else ...[
                          Text(
                            '최근 20개 평일 평균 ${effectiveInsight.averageText}건 대비 ${effectiveInsight.diffText}',
                            style: GoogleFonts.inter(
                              color: effectiveInsight.color,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '주말 제외 최근 평일 ${effectiveInsight.sampleCount}일 기준',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.42),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '전일 게시글 수와 당일 KOSPI 변동률',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (corrSnapshot.connectionState == ConnectionState.waiting)
                          const SizedBox(
                            height: 28,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          )
                        else if (correlation == null)
                          Text(
                            '상관관계를 계산할 만큼 아직 데이터가 부족합니다.',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.5),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          )
                        else ...[
                          Text(
                            '상관계수 ${correlation.correlationText}',
                            style: GoogleFonts.inter(
                              color: correlation.color,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            correlation.interpretation,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.58),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                          if (correlation.points.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: _FmkoreaScatterPlot(
                                points: correlation.points,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '표본 ${correlation.sampleCount}일 기준',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.42),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 88,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: chartEntries.map((entry) {
                        final ratio = (entry.count / maxCount).clamp(0.06, 1.0);
                        final isLatest = entry.dateKey == latest.dateKey;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FractionallySizedBox(
                                    heightFactor: ratio,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color: isLatest
                                            ? const Color(0xFF4ADE80)
                                            : const Color(
                                                0xFF4ADE80,
                                              ).withValues(alpha: 0.25),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry.dateKey.split('.').last,
                                  style: GoogleFonts.inter(
                                    color: isLatest
                                        ? const Color(0xFF16A34A)
                                        : cs.onSurface.withValues(alpha: 0.34),
                                    fontSize: 9,
                                    fontWeight: isLatest
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (updatedAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '업데이트 ${DateFormat('MM.dd HH:mm').format(updatedAt.toLocal())}',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.34),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  _FmkoreaWeekdayInsight? _computeWeekdayInsight(List<_FmkoreaDailyCount> entries) {
    if (entries.length < 5) return null;
    final baseline = entries
        .sublist(0, entries.length - 1)
        .where((entry) => entry.isWeekday)
        .toList()
        .reversed
        .take(20)
        .toList()
        .reversed
        .toList();
    if (baseline.length < 3) return null;

    final average =
        baseline.map((entry) => entry.count).reduce((a, b) => a + b) /
        baseline.length;
    final latest = entries.last;
    final diff = latest.count - average;
    final diffRate = average == 0 ? 0.0 : (diff / average) * 100;
    final color = diff >= 0
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return _FmkoreaWeekdayInsight(
      average: average,
      diff: diff,
      diffRate: diffRate,
      sampleCount: baseline.length,
      color: color,
    );
  }

  Future<_FmkoreaKospiCorrelation?> _computeKospiCorrelation(
    List<_FmkoreaDailyCount> entries,
  ) async {
    if (entries.length < 8) return null;

    final history = await StockPriceService.fetchHistoryDetailed(
      '^KS11',
      'US',
      range: '3y',
      interval: '1d',
    );
    if (history.length < 2) return null;

    final countByDate = {for (final entry in entries) entry.dateKey: entry.count.toDouble()};
    final xs = <double>[];
    final ys = <double>[];
    final points = <_FmkoreaScatterPoint>[];

    for (var i = 1; i < history.length; i++) {
      final current = history[i];
      final previous = history[i - 1];
      if (previous.$2 == 0) continue;
      final currentDate = DateTime(
        current.$1.year,
        current.$1.month,
        current.$1.day,
      );
      final prevKey = _previousWeekdayKey(currentDate);
      final postCount = countByDate[prevKey];
      if (postCount == null) continue;
      final changeRate = ((current.$2 - previous.$2) / previous.$2) * 100;
      xs.add(postCount);
      ys.add(changeRate);
      points.add(
        _FmkoreaScatterPoint(
          x: postCount,
          y: changeRate,
          label: DateFormat('yyyy.MM.dd').format(current.$1),
        ),
      );
    }

    if (xs.length < 5) return null;
    final corr = _pearson(xs, ys);
    if (corr == null) return null;
    return _FmkoreaKospiCorrelation(
      correlation: corr,
      sampleCount: xs.length,
      points: points,
    );
  }

  String _previousWeekdayKey(DateTime date) {
    var cursor = date.subtract(const Duration(days: 1));
    while (cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy.MM.dd').format(cursor);
  }

  double? _pearson(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.length < 2) return null;
    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;
    var numerator = 0.0;
    var denomX = 0.0;
    var denomY = 0.0;

    for (var i = 0; i < n; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      numerator += dx * dy;
      denomX += dx * dx;
      denomY += dy * dy;
    }

    final denominator = math.sqrt(denomX * denomY);
    if (denominator == 0) return null;
    return numerator / denominator;
  }

  Widget _buildFmkoreaMessage(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.42),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FmkoreaDailyCount {
  const _FmkoreaDailyCount({
    required this.dateKey,
    required this.count,
    required this.updatedAt,
  });

  final String dateKey;
  final int count;
  final DateTime? updatedAt;

  DateTime get parsedDate => DateFormat('yyyy.MM.dd').parse(dateKey);

  int get weekday => parsedDate.weekday;

  bool get isWeekday =>
      weekday >= DateTime.monday && weekday <= DateTime.friday;

  String get weekdayLabel {
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
    return labels[weekday - 1];
  }
}

class _FmkoreaWeekdayInsight {
  const _FmkoreaWeekdayInsight({
    required this.average,
    required this.diff,
    required this.diffRate,
    required this.sampleCount,
    required this.color,
  });

  final double average;
  final double diff;
  final double diffRate;
  final int sampleCount;
  final Color color;

  String get averageText => average.toStringAsFixed(0);

  String get diffText =>
      '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(0)}건(${diffRate >= 0 ? '+' : ''}${diffRate.toStringAsFixed(1)}%)';
}

class _FmkoreaKospiCorrelation {
  const _FmkoreaKospiCorrelation({
    required this.correlation,
    required this.sampleCount,
    required this.points,
  });

  final double correlation;
  final int sampleCount;
  final List<_FmkoreaScatterPoint> points;

  String get correlationText => correlation.toStringAsFixed(2);

  Color get color {
    if (correlation >= 0.2) return const Color(0xFF16A34A);
    if (correlation <= -0.2) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String get interpretation {
    final absValue = correlation.abs();
    if (absValue < 0.2) {
      return '지금 데이터 기준으로는 뚜렷한 선형 상관관계가 거의 없습니다.';
    }
    if (correlation > 0) {
      return '전날 게시글 수가 많을수록 당일 KOSPI 변동률도 높아지는 경향이 약하게 보입니다.';
    }
    return '전날 게시글 수가 많을수록 당일 KOSPI 변동률은 낮아지는 경향이 약하게 보입니다.';
  }
}

class _FmkoreaStoredSummary {
  const _FmkoreaStoredSummary({
    required this.weekdayInsight,
    required this.correlation,
  });

  final _FmkoreaWeekdayInsight? weekdayInsight;
  final _FmkoreaKospiCorrelation? correlation;

  factory _FmkoreaStoredSummary.fromMap(Map<String, dynamic> map) {
    final avg = (map['recent20WeekdayAverage'] as num?)?.toDouble();
    final diff = (map['recent20WeekdayDiff'] as num?)?.toDouble();
    final diffRate = (map['recent20WeekdayDiffRate'] as num?)?.toDouble();
    final sample = (map['recent20WeekdaySampleCount'] as num?)?.toInt() ?? 0;
    final corr = (map['correlation'] as num?)?.toDouble();
    final corrSample = (map['correlationSampleCount'] as num?)?.toInt() ?? 0;
    final scatterRaw = (map['scatterPoints'] as List<dynamic>? ?? const []);

    final weekdayInsight =
        avg == null || diff == null || diffRate == null || sample < 1
        ? null
        : _FmkoreaWeekdayInsight(
            average: avg,
            diff: diff,
            diffRate: diffRate,
            sampleCount: sample,
            color: diff >= 0
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
          );

    final points = scatterRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(
          (item) => _FmkoreaScatterPoint(
            x: (item['x'] as num?)?.toDouble() ?? 0,
            y: (item['y'] as num?)?.toDouble() ?? 0,
            label: (item['dateKey'] as String?) ?? '',
          ),
        )
        .toList();

    final correlation =
        corr == null || corrSample < 1
        ? null
        : _FmkoreaKospiCorrelation(
            correlation: corr,
            sampleCount: corrSample,
            points: points,
          );

    return _FmkoreaStoredSummary(
      weekdayInsight: weekdayInsight,
      correlation: correlation,
    );
  }
}

class _FmkoreaScatterPoint {
  const _FmkoreaScatterPoint({
    required this.x,
    required this.y,
    required this.label,
  });

  final double x;
  final double y;
  final String label;
}

class _FmkoreaScatterPlot extends StatelessWidget {
  const _FmkoreaScatterPlot({required this.points});

  final List<_FmkoreaScatterPoint> points;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min);
    final maxY = points.map((p) => p.y).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '가로축: 전일 게시글 수 · 세로축: 당일 KOSPI 변동률',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.58),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${maxY.toStringAsFixed(1)}%',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.42),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${minY.toStringAsFixed(1)}%',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.42),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _FmkoreaScatterPainter(
                            points: points,
                            axisColor: cs.onSurface.withValues(alpha: 0.18),
                            pointColor: const Color(0xFF16A34A),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            minX.toStringAsFixed(0),
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.42),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            maxX.toStringAsFixed(0),
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.42),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FmkoreaScatterPainter extends CustomPainter {
  const _FmkoreaScatterPainter({
    required this.points,
    required this.axisColor,
    required this.pointColor,
  });

  final List<_FmkoreaScatterPoint> points;
  final Color axisColor;
  final Color pointColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const leftPad = 10.0;
    const rightPad = 8.0;
    const topPad = 8.0;
    const bottomPad = 10.0;
    final chart = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min);
    final maxY = points.map((p) => p.y).reduce(math.max);
    final xSpan = maxX - minX == 0 ? 1.0 : maxX - minX;
    final ySpan = maxY - minY == 0 ? 1.0 : maxY - minY;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawRect(chart, axisPaint..style = PaintingStyle.stroke);

    if (minY <= 0 && maxY >= 0) {
      final zeroY = chart.bottom - ((0 - minY) / ySpan) * chart.height;
      canvas.drawLine(
        Offset(chart.left, zeroY),
        Offset(chart.right, zeroY),
        Paint()
          ..color = axisColor.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
    }

    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    for (final point in points) {
      final dx = chart.left + ((point.x - minX) / xSpan) * chart.width;
      final dy = chart.bottom - ((point.y - minY) / ySpan) * chart.height;
      canvas.drawCircle(Offset(dx, dy), 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FmkoreaScatterPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.pointColor != pointColor;
  }
}
