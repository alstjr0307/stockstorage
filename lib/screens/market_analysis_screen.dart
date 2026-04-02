import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/market_analysis.dart';
import '../services/ad_service.dart';
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
    ('WTI 오일', 'CL=F'),
  ];

  static const _indexDescriptions = {
    'KOSPI': '한국 대형주 종합지수',
    'KOSDAQ': '한국 성장주 중심 시장',
    'S&P 500': '미국 대표 500대 기업',
    'NASDAQ': '미국 기술주 중심 지수',
    'USD/KRW': '원달러 환율',
    '나스닥100 선물': '미국 장전 분위기',
    'WTI 오일': '국제유가 선행 흐름',
  };

  static const _indexAccentColors = {
    'KOSPI': Color(0xFF22C55E),
    'KOSDAQ': Color(0xFF10B981),
    'S&P 500': Color(0xFF3B82F6),
    'NASDAQ': Color(0xFF6366F1),
    'USD/KRW': Color(0xFFF59E0B),
    '나스닥100 선물': Color(0xFFF97316),
    'WTI 오일': Color(0xFFEF4444),
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
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.74,
          children: [
            _IndicatorShortcutCard(
              title: '외인 · 기관 수급',
              subtitle: '외국인·기관 순매수\nTOP5 종목',
              icon: Icons.candlestick_chart_rounded,
              accent: const Color(0xFFF59E0B),
              onTap: () {
                AdService.instance.showIndicatorDetailInterstitialIfReady();
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
                AdService.instance.showIndicatorDetailInterstitialIfReady();
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
                AdService.instance.showIndicatorDetailInterstitialIfReady();
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
    return Column(
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
          itemCount: _indices.length - 1,
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
        const SizedBox(height: 12),
        _buildWideIndexCard(context, 'WTI 오일', 'CL=F'),
      ],
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: isDark ? 0.14 : 0.10),
            width: 1,
          ),
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
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
                    const SizedBox(height: 5),
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
          ],
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildAnalysisSummaryItem(
                      context,
                      icon: Icons.schedule_rounded,
                      label: '최신 업데이트',
                      primaryValue: latestDate == null
                          ? '-'
                          : DateFormat('yyyy.MM.dd').format(latestDate),
                      secondaryValue: latestDate == null
                          ? null
                          : DateFormat('HH:mm').format(latestDate),
                      accentColor: const Color(0xFF16A34A),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: cs.onSurface.withValues(alpha: 0.08),
                  ),
                  Expanded(
                    child: _buildAnalysisSummaryItem(
                      context,
                      icon: Icons.feed_outlined,
                      label: '글 개수',
                      primaryValue: '${list.length}개',
                      accentColor: const Color(0xFF0EA5E9),
                    ),
                  ),
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

  Widget _buildWideIndexCard(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _prices[name];
    final accent = _indexAccentColors[name] ?? const Color(0xFF4ADE80);
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: isDark ? 0.14 : 0.10),
            width: 1,
          ),
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.local_gas_station_rounded,
                                  color: accent,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _indexDescriptions[name] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.48),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_loadingIndices && result == null)
                            const SizedBox(
                              width: 18,
                              height: 18,
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
                              style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontSize: 20,
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
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(BuildContext context, MarketAnalysis analysis) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = analysis.imageUrls.isNotEmpty;
    final preview = analysis.body.replaceAll('\n', ' ').trim();
    final dateLabel = DateFormat('yyyy.MM.dd HH:mm').format(analysis.createdAt);

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
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              dateLabel,
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.62),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            hasImage
                                ? Icons.insert_photo_outlined
                                : Icons.article_outlined,
                            size: 17,
                            color: cs.onSurface.withValues(alpha: 0.38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        analysis.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        preview.isEmpty ? '본문이 없습니다.' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.58),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (hasImage)
                            Text(
                              '이미지 포함',
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.42),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '자세히 보기',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.52),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.onSurface.withValues(alpha: 0.38),
                          ),
                        ],
                      ),
                    ],
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

  Widget _buildAnalysisSummaryItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String primaryValue,
    String? secondaryValue,
    required Color accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 16,
            color: accentColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                primaryValue,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (secondaryValue != null) ...[
                const SizedBox(height: 2),
                Text(
                  secondaryValue,
                  style: GoogleFonts.inter(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
                maxLines: 2,
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

class _InvestorFlowDetailScreen extends StatefulWidget {
  const _InvestorFlowDetailScreen();

  @override
  State<_InvestorFlowDetailScreen> createState() =>
      _InvestorFlowDetailScreenState();
}

class _InvestorFlowDetailScreenState extends State<_InvestorFlowDetailScreen> {
  final _captureKey = GlobalKey();
  bool _capturing = false;
  bool _showWatermark = false;

  String _shareText() {
    return '주식저장소 마감수급\n\n'
        '외국인과 기관이 가장 많이 순매수한 종목을 한눈에 확인해보세요.\n\n'
        'https://stockstorage-13828.web.app';
  }

  Future<void> _captureAndShare() async {
    if (_capturing) return;

    setState(() {
      _capturing = true;
      _showWatermark = true;
    });

    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/investor_flow_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '주식저장소 마감수급',
      );
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _showWatermark = false;
        });
      }
    }
  }

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
              '마감수급',
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '외국인과 기관이 가장 많이 순매수한 종목',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '공유하기',
            onPressed: () => Share.share(_shareText()),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  children: [
                    const _InvestorFlowCard(),
                    if (_showWatermark) ...[
                      const SizedBox(height: 12),
                      Text(
                        '주식저장소 앱에서 확인하세요.',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _capturing ? null : _captureAndShare,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: _capturing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.image_outlined, size: 20),
                label: Text(
                  '캡처해서 공유하기',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _FmkoreaIndexDetailScreen extends StatefulWidget {
  const _FmkoreaIndexDetailScreen();

  @override
  State<_FmkoreaIndexDetailScreen> createState() =>
      _FmkoreaIndexDetailScreenState();
}

class _FmkoreaIndexDetailScreenState extends State<_FmkoreaIndexDetailScreen> {
  final _captureKey = GlobalKey();
  bool _capturing = false;
  bool _showWatermark = false;

  Future<void> _captureAndShare() async {
    if (_capturing) return;

    setState(() {
      _capturing = true;
      _showWatermark = true;
    });

    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/fmkorea_index_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '주식저장소 펨코지수',
      );
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _showWatermark = false;
        });
      }
    }
  }

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
              '펨코지수',
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '게시글 수와 KOSPI 흐름 비교',
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
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  children: [
                    const _FmkoreaIndexCard(),
                    if (_showWatermark) ...[
                      const SizedBox(height: 12),
                      Text(
                        '주식저장소 앱에서 확인하세요.',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _capturing ? null : _captureAndShare,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: _capturing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.image_outlined, size: 20),
                label: Text(
                  '캡처해서 공유하기',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
        final todayKey = DateFormat('yyyy.MM.dd').format(DateTime.now());
        final todayMatches = entries
            .where((entry) => entry.dateKey == todayKey)
            .toList();
        final todayEntry = todayMatches.isEmpty ? null : todayMatches.last;
        final focusedEntry =
            todayEntry != null && entries.length >= 2 && latest.dateKey == todayKey
            ? entries[entries.length - 2]
            : latest;
        final recentEntries = entries.length > 7
            ? entries.sublist(entries.length - 7)
            : entries;
        final chartEntries = entries.length > 20
            ? entries.sublist(entries.length - 20)
            : entries;
        final updatedAt = entries
            .map((entry) => entry.updatedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (acc, item) {
              if (acc == null) return item;
              return item.isAfter(acc) ? item : acc;
            });
        final weekdayInsight = _computeWeekdayInsight(entries, focusedEntry);

        return FutureBuilder<_FmkoreaKospiSnapshot?>(
          future: _computeKospiSnapshot(entries),
          builder: (context, corrSnapshot) {
            final kospiSnapshot = corrSnapshot.data;
            final effectiveInsight = weekdayInsight;
            final focusedKospiChange =
                kospiSnapshot?.sameDayChangeByDate[focusedEntry.dateKey];
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFmkoreaCountSummaryCard(
                          context,
                          label: focusedEntry.dateKey == latest.dateKey
                              ? '최근 마감 게시글 수'
                              : '전일 마감 게시글 수',
                          dateKey: focusedEntry.dateKey,
                          count: focusedEntry.count,
                          accentColor: const Color(0xFF16A34A),
                          subtitle: focusedKospiChange == null
                              ? '전일 KOSPI 변동률 집계 전'
                              : '전일 KOSPI ${_formatSignedPercent(focusedKospiChange)}',
                          subtitleColor: focusedKospiChange == null
                              ? null
                              : focusedKospiChange >= 0
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626),
                          insight: effectiveInsight,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFmkoreaCountSummaryCard(
                          context,
                          label: '오늘 현재까지',
                          dateKey: todayEntry?.dateKey ?? todayKey,
                          count: todayEntry?.count ?? 0,
                          accentColor: const Color(0xFF0EA5E9),
                          subtitle: todayEntry == null
                              ? '아직 오늘 집계가 없습니다.'
                              : '진행 중인 누적 게시글 수',
                          updatedAt: todayEntry?.updatedAt,
                        ),
                      ),
                    ],
                  ),
                  if (effectiveInsight != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: effectiveInsight.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: effectiveInsight.color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_fire_department_outlined,
                            size: 16,
                            color: effectiveInsight.color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '현재 열기 ${effectiveInsight.heatLabel} · 평균 대비 ${effectiveInsight.diffRateText}',
                              style: GoogleFonts.inter(
                                color: effectiveInsight.color,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                          '최근 20일 게시글 수 · KOSPI 변동률',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '막대는 게시글 수, 선은 KOSPI 변동률입니다.',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 180,
                          child: _FmkoreaTrendChart(
                            points: chartEntries
                                .map(
                                  (entry) => _FmkoreaTrendPoint(
                                    dateKey: entry.dateKey,
                                    count: entry.count,
                                    kospiChange: kospiSnapshot
                                        ?.sameDayChangeByDate[entry.dateKey],
                                    isToday: entry.dateKey == todayKey,
                                    isWeekend: !entry.isWeekday,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
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
                          '최근 날짜별 게시글 수 · KOSPI 변동률',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '각 날짜 기준 KOSPI 변동률입니다.',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...recentEntries.reversed.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildFmkoreaDailyRow(
                              context,
                              entry: entry,
                              kospiChange:
                                  kospiSnapshot?.sameDayChangeByDate[entry.dateKey],
                              isToday: entry.dateKey == todayKey,
                              isFocused: entry.dateKey == focusedEntry.dateKey,
                              isWeekend: !entry.isWeekday,
                              updatedAt: entry.updatedAt,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
              );
          },
        );
      },
    );
  }

  _FmkoreaWeekdayInsight? _computeWeekdayInsight(
    List<_FmkoreaDailyCount> entries,
    _FmkoreaDailyCount target,
  ) {
    if (entries.length < 5) return null;
    final targetIndex = entries.indexWhere((entry) => entry.dateKey == target.dateKey);
    if (targetIndex <= 0) return null;
    final baseline = entries
        .sublist(0, targetIndex)
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
    final diff = target.count - average;
    final diffRate = average == 0 ? 0.0 : (diff / average) * 100;
    final color = diffRate >= 35
        ? const Color(0xFFDC2626)
        : diffRate >= 15
            ? const Color(0xFFF97316)
            : diffRate >= -10
                ? const Color(0xFF16A34A)
                : diffRate >= -25
                    ? const Color(0xFF0EA5E9)
                    : const Color(0xFF2563EB);

    return _FmkoreaWeekdayInsight(
      average: average,
      diff: diff,
      diffRate: diffRate,
      sampleCount: baseline.length,
      color: color,
    );
  }

  Future<_FmkoreaKospiSnapshot?> _computeKospiSnapshot(
    List<_FmkoreaDailyCount> entries,
  ) async {
    if (entries.isEmpty) return null;

    final history = await StockPriceService.fetchHistoryDetailed(
      '^KS11',
      'US',
      range: '3y',
      interval: '1d',
    );
    if (history.length < 2) return null;

    final countByDate = {for (final entry in entries) entry.dateKey: entry.count.toDouble()};
    final sameDayChangeByDate = <String, double>{};
    final xs = <double>[];
    final ys = <double>[];
    final points = <_FmkoreaScatterPoint>[];

    for (var i = 1; i < history.length; i++) {
      final current = history[i];
      final previous = history[i - 1];
      if (previous.$2 == 0) continue;
      final currentTime = current.$1;
      final currentDate = DateTime(
        currentTime.year,
        currentTime.month,
        currentTime.day,
      );
      final changeRate = ((current.$2 - previous.$2) / previous.$2) * 100;
      final prevKey = _previousWeekdayKey(currentDate);
      final currentKey = DateFormat('yyyy.MM.dd').format(currentTime);
      sameDayChangeByDate[currentKey] = changeRate;
      final postCount = countByDate[prevKey];
      if (postCount == null) continue;
      xs.add(postCount);
      ys.add(changeRate);
      points.add(
        _FmkoreaScatterPoint(
          x: postCount,
          y: changeRate,
          label: DateFormat('yyyy.MM.dd').format(currentTime),
        ),
      );
    }

    final correlation = (() {
      if (xs.length < 5) return null;
      final corr = _pearson(xs, ys);
      if (corr == null) return null;
      return _FmkoreaKospiCorrelation(
        correlation: corr,
        sampleCount: xs.length,
        points: points,
      );
    })();

    return _FmkoreaKospiSnapshot(
      sameDayChangeByDate: sameDayChangeByDate,
      correlation: correlation,
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

  Widget _buildFmkoreaCountSummaryCard(
    BuildContext context, {
    required String label,
    required String dateKey,
    required int count,
    required Color accentColor,
    required String subtitle,
    Color? subtitleColor,
    _FmkoreaWeekdayInsight? insight,
    DateTime? updatedAt,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.10),
            cs.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.52),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateKey,
            style: GoogleFonts.inter(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
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
          if (insight != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '평균 대비',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.58),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight.diffRateText,
                    style: GoogleFonts.inter(
                      color: insight.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: subtitleColor ?? cs.onSurface.withValues(alpha: 0.52),
              fontSize: 11,
              fontWeight: subtitleColor == null
                  ? FontWeight.w600
                  : FontWeight.w700,
              height: 1.45,
            ),
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '최종 집계 ${DateFormat('HH:mm').format(updatedAt.toLocal())}',
              style: GoogleFonts.inter(
                color: accentColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFmkoreaDailyRow(
    BuildContext context, {
    required _FmkoreaDailyCount entry,
    required double? kospiChange,
    required bool isToday,
    required bool isFocused,
    required bool isWeekend,
    DateTime? updatedAt,
  }) {
    final cs = Theme.of(context).colorScheme;
    final changeColor = kospiChange == null
        ? cs.onSurface.withValues(alpha: 0.42)
        : kospiChange >= 0
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFF4ADE80).withValues(alpha: 0.08)
            : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFocused
              ? const Color(0xFF4ADE80).withValues(alpha: 0.24)
              : cs.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.dateKey,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '오늘',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF0284C7),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '게시글 ${entry.count}건',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.56),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isToday && updatedAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '기준 ${DateFormat('HH:mm').format(updatedAt.toLocal())}',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF0284C7),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'KOSPI',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.42),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isWeekend && kospiChange == null
                    ? '주말'
                    : kospiChange == null
                        ? '-'
                        : _formatSignedPercent(kospiChange),
                style: GoogleFonts.inter(
                  color: isWeekend && kospiChange == null
                      ? const Color(0xFFF59E0B)
                      : changeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSignedPercent(double value) {
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
  }
}

class _FmkoreaTrendPoint {
  const _FmkoreaTrendPoint({
    required this.dateKey,
    required this.count,
    required this.kospiChange,
    required this.isToday,
    required this.isWeekend,
  });

  final String dateKey;
  final int count;
  final double? kospiChange;
  final bool isToday;
  final bool isWeekend;
}

class _FmkoreaTrendChart extends StatefulWidget {
  const _FmkoreaTrendChart({required this.points});

  final List<_FmkoreaTrendPoint> points;

  @override
  State<_FmkoreaTrendChart> createState() => _FmkoreaTrendChartState();
}

class _FmkoreaTrendChartState extends State<_FmkoreaTrendChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.points.isEmpty) {
      return Center(
        child: Text(
          '차트 데이터가 없습니다.',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.42),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_selectedIndex != null) ...[
          _buildSelectionCard(context, widget.points[_selectedIndex!]),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            _buildLegend(
              context,
              color: const Color(0xFF4ADE80),
              label: '게시글 수',
            ),
            const SizedBox(width: 12),
            _buildLegend(
              context,
              color: const Color(0xFF0EA5E9),
              label: 'KOSPI',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _selectPoint(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragStart: (details) =>
                    _selectPoint(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    _selectPoint(details.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  painter: _FmkoreaTrendPainter(
                    points: widget.points,
                    axisColor: cs.onSurface.withValues(alpha: 0.14),
                    textColor: cs.onSurface.withValues(alpha: 0.42),
                    selectedIndex: _selectedIndex,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionCard(BuildContext context, _FmkoreaTrendPoint point) {
    final cs = Theme.of(context).colorScheme;
    final kospiText = point.kospiChange == null
        ? '-'
        : '${point.kospiChange! >= 0 ? '+' : ''}${point.kospiChange!.toStringAsFixed(2)}%';
    final kospiColor = point.kospiChange == null
        ? cs.onSurface.withValues(alpha: 0.5)
        : point.kospiChange! >= 0
            ? const Color(0xFF0EA5E9)
            : const Color(0xFFDC2626);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              point.dateKey,
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '게시글 ${point.count}건',
            style: GoogleFonts.inter(
              color: const Color(0xFF16A34A),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'KOSPI $kospiText',
            style: GoogleFonts.inter(
              color: kospiColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _selectPoint(double dx, double width) {
    if (widget.points.isEmpty || width <= 42) return;
    const leftPad = 34.0;
    const rightPad = 8.0;
    final chartWidth = width - leftPad - rightPad;
    if (chartWidth <= 0) return;
    final step = chartWidth / widget.points.length;
    final rawIndex = ((dx - leftPad) / step).floor();
    final index = rawIndex.clamp(0, widget.points.length - 1);
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  Widget _buildLegend(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.56),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FmkoreaTrendPainter extends CustomPainter {
  const _FmkoreaTrendPainter({
    required this.points,
    required this.axisColor,
    required this.textColor,
    required this.selectedIndex,
  });

  final List<_FmkoreaTrendPoint> points;
  final Color axisColor;
  final Color textColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 34.0;
    const rightPad = 8.0;
    const topPad = 8.0;
    const bottomPad = 20.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final barStep = chartWidth / points.length;
    final maxCount = points.fold<int>(1, (m, p) => p.count > m ? p.count : m);
    final changes = points
        .map((p) => p.kospiChange)
        .whereType<double>()
        .toList();
    final maxAbsChange = changes.isEmpty
        ? 1.0
        : changes
            .map((v) => v.abs())
            .fold<double>(1.0, (m, v) => v > m ? v : m);

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    _paintAxisLabel(
      canvas,
      text: '0%',
      x: 6,
      y: topPad + (chartHeight * 0.5) - 7,
    );
    _paintAxisLabel(
      canvas,
      text: '${maxAbsChange.toStringAsFixed(1)}%',
      x: 0,
      y: topPad + 4,
      color: const Color(0xFF0EA5E9),
    );
    _paintAxisLabel(
      canvas,
      text: '-${maxAbsChange.toStringAsFixed(1)}%',
      x: 0,
      y: topPad + chartHeight - 14,
      color: const Color(0xFF0EA5E9),
    );
    canvas.drawLine(
      Offset(leftPad, topPad + chartHeight),
      Offset(leftPad + chartWidth, topPad + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(leftPad, topPad + (chartHeight * 0.5)),
      Offset(leftPad + chartWidth, topPad + (chartHeight * 0.5)),
      Paint()
        ..color = axisColor.withValues(alpha: 0.8)
        ..strokeWidth = 1,
    );

    final barPaint = Paint()..color = const Color(0xFF4ADE80).withValues(alpha: 0.45);
    final todayBarPaint = Paint()..color = const Color(0xFF16A34A);
    final weekendBarPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.28);
    final linePaint = Paint()
      ..color = const Color(0xFF0EA5E9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    var hasLineStart = false;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = leftPad + (barStep * i) + barStep / 2;
      if (selectedIndex == i) {
        canvas.drawLine(
          Offset(x, topPad),
          Offset(x, topPad + chartHeight),
          Paint()
            ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.28)
            ..strokeWidth = 1,
        );
      }
      final barHeight = maxCount == 0 ? 0.0 : (point.count / maxCount) * (chartHeight * 0.78);
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x - (barStep * 0.28),
          topPad + chartHeight - barHeight,
          barStep * 0.56,
          barHeight,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        barRect,
        point.isToday
            ? todayBarPaint
            : point.isWeekend
                ? weekendBarPaint
                : barPaint,
      );

      if (point.kospiChange != null) {
        final normalized = (point.kospiChange! / maxAbsChange).clamp(-1.0, 1.0);
        final y = topPad + (chartHeight * 0.5) - (normalized * (chartHeight * 0.34));
        if (!hasLineStart) {
          path.moveTo(x, y);
          hasLineStart = true;
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(
          Offset(x, y),
          2.8,
          Paint()..color = const Color(0xFF0EA5E9),
        );
      }

      if (i % 4 == 0 || i == points.length - 1) {
        final label = points[i].dateKey.split('.').sublist(1).join('.');
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: GoogleFonts.inter(
              color: textColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, topPad + chartHeight + 6),
        );
      }
    }

    if (hasLineStart) {
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FmkoreaTrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.selectedIndex != selectedIndex;
  }

  void _paintAxisLabel(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    Color? color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.inter(
          color: color ?? textColor,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
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
  String get diffRateText =>
      '${diffRate >= 0 ? '+' : ''}${diffRate.toStringAsFixed(1)}%';
  String get heatLabel {
    if (diffRate >= 35) return '매우 뜨거움';
    if (diffRate >= 15) return '뜨거움';
    if (diffRate >= -10) return '보통';
    if (diffRate >= -25) return '차분함';
    return '매우 차분함';
  }

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

class _FmkoreaKospiSnapshot {
  const _FmkoreaKospiSnapshot({
    required this.sameDayChangeByDate,
    required this.correlation,
  });

  final Map<String, double> sameDayChangeByDate;
  final _FmkoreaKospiCorrelation? correlation;
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
