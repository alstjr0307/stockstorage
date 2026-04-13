import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fmkorea_stock_mention.dart';
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
  final _firestoreService = FirestoreService();
  final GlobalKey _fmkoreaHotShareCardKey = GlobalKey();
  int _fmkoreaHotTabIndex = 0;
  late Future<FmkoreaStockMentionsSnapshot?> _previousDailyHotFuture;

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
    'KOSPI': Color(0xFF3182F6),
    'KOSDAQ': Color(0xFF00C4B4),
    'S&P 500': Color(0xFF6366F1),
    'NASDAQ': Color(0xFF8B5CF6),
    'USD/KRW': Color(0xFFF59E0B),
    '나스닥100 선물': Color(0xFFF97316),
    'WTI 오일': Color(0xFFEF4444),
  };

  static final _analysisFmt = DateFormat('MM.dd HH:mm');

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;
  int _indicesRequestSerial = 0;
  DateTime? _indicesFetchedAt;

  @override
  void initState() {
    super.initState();
    _previousDailyHotFuture = _firestoreService
        .getPreviousDailyFmkoreaStockMentions();
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
    setState(() {
      _previousDailyHotFuture = _firestoreService
          .getPreviousDailyFmkoreaStockMentions();
    });
    await _fetchIndices(forceRefresh: true);
  }

  Future<void> _openFmkoreaHotShareSheet(
    BuildContext context,
    FmkoreaStockMentionsSnapshot data,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FmkoreaHotShareSheet(
        shareCardKey: _fmkoreaHotShareCardKey,
        data: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildTopTabBar(context),
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
    return TabBar(
      labelStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      labelColor: cs.onSurface,
      unselectedLabelColor: cs.onSurface.withValues(alpha: 0.38),
      dividerColor: Colors.transparent,
      indicator: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: 0.1)
            : cs.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9999),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      tabs: const [
        Tab(text: '지표'),
        Tab(text: '시황분석'),
      ],
    );
  }

  Widget _buildIndicatorsTab(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF3182F6),
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          _StaggerReveal(
            onceKey: 'major_indices_section_once_v4',
            delay: const Duration(milliseconds: 40),
            child: _buildIndicesPanel(context),
          ),
          const SizedBox(height: 16),
          _buildSectionDivider(context),
          const SizedBox(height: 16),
          _StaggerReveal(
            delay: const Duration(milliseconds: 95),
            child: _buildFmkoreaMentionsSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionDivider(context),
          const SizedBox(height: 16),
          _StaggerReveal(
            onceKey: 'indicator_shortcuts_section_once_v4',
            delay: const Duration(milliseconds: 140),
            child: _buildIndicatorShortcuts(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 2.2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF10B981).withValues(alpha: 0.08),
                  const Color(0xFF10B981).withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 2.2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF10B981).withValues(alpha: 0.55),
                  const Color(0xFF10B981).withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorShortcuts(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      (
        title: '외인 · 기관 수급',
        subtitle: '외국인·기관 순매수 TOP5 종목',
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
      (
        title: '시장 심리 지표',
        subtitle: '공포/탐욕 · 시장 온도',
        icon: Icons.psychology_alt_rounded,
        accent: const Color(0xFF3182F6),
        onTap: () {
          AdService.instance.showIndicatorDetailInterstitialIfReady();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MarketSentimentScreen()),
          );
        },
      ),
      (
        title: '펨코지수',
        subtitle: '커뮤니티 흐름 · KOSPI 비교',
        icon: Icons.forum_rounded,
        accent: const Color(0xFF6366F1),
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '세부 지표',
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _StaggerReveal(
                onceKey: 'indicator_shortcut_row_once_v4_$i',
                delay: Duration(milliseconds: 110 + (i * 120)),
                child: _IndicatorShortcutCard(
                  title: items[i].title,
                  subtitle: items[i].subtitle,
                  icon: items[i].icon,
                  accent: items[i].accent,
                  onTap: items[i].onTap,
                ),
              ),
              if (i < items.length - 1)
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(left: 8 + 36 + 10),
                  color: cs.onSurface.withValues(alpha: 0.06),
                ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFmkoreaMentionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget emptyMessage(String text) {
      return Text(
        text,
        style: GoogleFonts.inter(
          color: cs.onSurface.withValues(alpha: 0.45),
          fontSize: 12,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _fmkoreaHotTabIndex = 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _fmkoreaHotTabIndex == 0
                          ? cs.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '\uC624\uB298 \uC2E4\uC2DC\uAC04',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: _fmkoreaHotTabIndex == 0
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: _fmkoreaHotTabIndex == 0
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _fmkoreaHotTabIndex = 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _fmkoreaHotTabIndex == 1
                          ? cs.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '\uC804\uC77C HOT',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: _fmkoreaHotTabIndex == 1
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: _fmkoreaHotTabIndex == 1
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_fmkoreaHotTabIndex == 0)
          StreamBuilder<FmkoreaStockMentionsSnapshot?>(
            stream: _firestoreService.getRealtimeOnlyFmkoreaStockMentions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF10B981),
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return emptyMessage(
                  '\uC2E4\uC2DC\uAC04 HOT \uB370\uC774\uD130\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
                );
              }
              final realtime = snapshot.data;
              if (realtime == null || realtime.topMentions.isEmpty) {
                return emptyMessage(
                  '\uC624\uB298 \uC2E4\uC2DC\uAC04 HOT \uB370\uC774\uD130\uAC00 \uC544\uC9C1 \uC5C6\uC2B5\uB2C8\uB2E4.',
                );
              }
              return _buildFmkoreaMentionsRows(
                context,
                title:
                    '\uD3A8\uCF54 \uC624\uB298 \uC2E4\uC2DC\uAC04 HOT \uC885\uBAA9',
                data: realtime,
                isRealtime: true,
              );
            },
          )
        else
          FutureBuilder<FmkoreaStockMentionsSnapshot?>(
            future: _previousDailyHotFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF10B981),
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return emptyMessage(
                  '\uC804\uC77C HOT \uB370\uC774\uD130\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
                );
              }
              final daily = snapshot.data;
              if (daily == null || daily.topMentions.isEmpty) {
                return emptyMessage(
                  '\uD45C\uC2DC\uD560 \uC804\uC77C HOT \uB370\uC774\uD130\uAC00 \uC544\uC9C1 \uC5C6\uC2B5\uB2C8\uB2E4.',
                );
              }
              return _buildFmkoreaMentionsRows(
                context,
                title: '\uD3A8\uCF54 \uC804\uC77C HOT \uC885\uBAA9',
                data: daily,
              );
            },
          ),
      ],
    );
  }

  Widget _buildFmkoreaMentionsRows(
    BuildContext context, {
    required String title,
    required FmkoreaStockMentionsSnapshot data,
    bool isRealtime = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final rows = data.topMentions.take(10).toList();
    final updatedAt = data.updatedAt == null
        ? null
        : DateFormat('MM.dd HH:mm').format(data.updatedAt!);

    Widget buildMentionRow(int i) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF10B981,
                    ).withValues(alpha: i < 3 ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.robotoMono(
                      color: const Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].name.isEmpty ? rows[i].ticker : rows[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rows[i].ticker,
                        style: GoogleFonts.robotoMono(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rows[i].mentionCount}회',
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFF10B981),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (i < rows.length - 1)
            Container(
              margin: const EdgeInsets.only(left: 46, right: 12),
              height: 1.2,
              color: cs.onSurface.withValues(alpha: 0.12),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('🔥', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildHotTitle(title, cs)),
            if (isRealtime) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: '공유',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openFmkoreaHotShareSheet(context, data),
                icon: const Icon(
                  Icons.ios_share_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          updatedAt == null
              ? '업데이트 시간 정보 없음 · 커뮤니티 열기 기준'
              : '업데이트 $updatedAt · 게시글 ${data.totalPosts}개 집계',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
          ),
          child: _VisibilityTriggered(
            enabled: isRealtime,
            childWhenInactive: Column(
              children: [
                for (var i = 0; i < rows.length; i++) buildMentionRow(i),
              ],
            ),
            builder: () => Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _StaggerReveal(
                    key: ValueKey(
                      '${data.mode}|${data.dateKey}|${data.updatedAt?.millisecondsSinceEpoch ?? 0}|'
                      '${rows[i].ticker}|${rows[i].mentionCount}|$i',
                    ),
                    delay: Duration(milliseconds: 220 + (i * 120)),
                    child: buildMentionRow(i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHotTitle(String title, ColorScheme cs) {
    final hotIdx = title.indexOf('HOT');
    final baseStyle = GoogleFonts.inter(
      color: cs.onSurface,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    );
    if (hotIdx < 0) {
      return Text(title, style: baseStyle);
    }

    final prefix = title.substring(0, hotIdx);
    final suffix = title.substring(hotIdx + 3);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: 'HOT',
            style: baseStyle.copyWith(
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: suffix),
        ],
      ),
    );
  }

  Widget _buildIndicesPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StaggerReveal(
          onceKey: 'major_indices_header_once_v4',
          delay: const Duration(milliseconds: 40),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '주요 지수',
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _indicesFetchedAt == null
                          ? '핵심 시장 지수를 빠르게 확인하세요'
                          : '기준 ${DateFormat('HH:mm').format(_indicesFetchedAt!)}',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
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
                    color: Color(0xFF3182F6),
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
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _indices.length; i++) ...[
          _StaggerReveal(
            onceKey: 'major_indices_row_once_v4_${_indices[i].$1}',
            delay: Duration(milliseconds: 120 + (i * 90)),
            duration: const Duration(milliseconds: 420),
            beginOffset: const Offset(0, 0.12),
            child: _buildIndexRow(context, _indices[i].$1, _indices[i].$2),
          ),
          if (i < _indices.length - 1)
            Container(
              margin: const EdgeInsets.only(left: 40),
              height: 1,
              color: cs.onSurface.withValues(alpha: 0.07),
            ),
        ],
      ],
    );
  }

  Widget _buildIndexRow(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
    final result = _prices[name];
    final accent = _indexAccentColors[name] ?? const Color(0xFF3182F6);
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildIndexBadgeGlyph(name, accent, 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _indexDescriptions[name] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (_loadingIndices && result == null)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF3182F6),
                ),
              )
            else if (result == null)
              Text(
                '--',
                style: GoogleFonts.robotoMono(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _displayValue(name, result),
                    style: GoogleFonts.robotoMono(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
                    style: GoogleFonts.robotoMono(
                      color: moveColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndexCard(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _prices[name];
    final accent = _indexAccentColors[name] ?? const Color(0xFF3182F6);
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.08),
            width: 1,
          ),
          color: cs.surface,
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _buildIndexBadgeGlyph(name, accent, 16),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: cs.onSurface.withValues(alpha: 0.22),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _indexDescriptions[name] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (_loadingIndices && result == null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3182F6),
                  ),
                )
              else if (result == null)
                Text(
                  '--',
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                Text(
                  _displayValue(name, result),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 7),
                _buildChangeRateBadge(moveColor, isUp, result.changeRate),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangeRateBadge(Color color, bool isUp, double changeRate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: color,
            size: 12,
          ),
          const SizedBox(width: 3),
          Text(
            '${isUp ? '+' : ''}${changeRate.toStringAsFixed(2)}%',
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
            child: CircularProgressIndicator(color: Color(0xFF3182F6)),
          );
        }

        final list = snapshot.data ?? [];
        final latestDate = list.isEmpty
            ? null
            : list
                  .map((item) => item.createdAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            _StaggerReveal(
              delay: const Duration(milliseconds: 40),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestDate == null
                              ? '등록된 분석이 없습니다'
                              : '최신 ${_analysisFmt.format(latestDate)} · 총 ${list.length}개',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (list.isEmpty)
              _StaggerReveal(
                delay: const Duration(milliseconds: 140),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 30,
                          color: cs.onSurface.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '등록된 시황 분석이 없습니다.',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              for (var i = 0; i < list.length; i++) ...[
                if (i < 8)
                  _StaggerReveal(
                    delay: Duration(milliseconds: 100 + (i * 30)),
                    child: _buildAnalysisCard(context, list[i]),
                  )
                else
                  _buildAnalysisCard(context, list[i]),
                if (i < list.length - 1)
                  Container(
                    margin: const EdgeInsets.only(left: 2),
                    height: 1,
                    color: cs.onSurface.withValues(alpha: 0.07),
                  ),
              ],
          ],
        );
      },
    );
  }

  Widget _buildWideIndexCard(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _prices[name];
    final accent = _indexAccentColors[name] ?? const Color(0xFF3182F6);
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.08),
            width: 1,
          ),
          color: cs.surface,
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: _buildIndexBadgeGlyph(name, accent, 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _indexDescriptions[name] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_loadingIndices && result == null)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3182F6),
                  ),
                )
              else if (result == null)
                Text(
                  '--',
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _displayValue(name, result),
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildChangeRateBadge(moveColor, isUp, result.changeRate),
                  ],
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
    final dateLabel = _analysisFmt.format(analysis.createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MarketAnalysisDetailScreen(analysis: analysis),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    dateLabel,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasImage)
                  Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              analysis.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3,
                letterSpacing: -0.5,
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 15,
                  height: 1.65,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _indexIconFor(String name) {
    switch (name) {
      case 'KOSPI':
      case 'KOSDAQ':
        return Icons.show_chart_rounded;
      case 'S&P 500':
        return Icons.account_balance_rounded;
      case 'NASDAQ':
        return Icons.memory_rounded;
      case 'WTI 오일':
        return Icons.local_gas_station_rounded;
      default:
        return Icons.trending_up_rounded;
    }
  }

  Widget _buildIndexBadgeGlyph(String name, Color accent, double size) {
    final emoji = _indexEmojiFor(name);
    if (emoji != null) {
      return Center(
        child: Text(emoji, style: TextStyle(fontSize: size, height: 1)),
      );
    }
    return Icon(_indexIconFor(name), color: accent, size: size);
  }

  String? _indexEmojiFor(String name) {
    if (name == 'USD/KRW') return '💱';
    return null;
  }
}

class _InvestorFlowCard extends StatelessWidget {
  const _InvestorFlowCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('market_investor_flow')
          .orderBy('marketDate', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        return Container(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
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
            color: Color(0xFF3182F6),
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
        _StaggerReveal(
          delay: const Duration(milliseconds: 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '마감 수급 TOP5',
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '순매수 금액 기준 · 외인/기관 상위 5종목',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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
                  data.marketDate,
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _StaggerReveal(
          delay: const Duration(milliseconds: 120),
          child: _InvestorFlowMarketBlock(
            marketLabel: 'KOSPI',
            foreignTop5: data.kospiForeignTop5,
            institutionTop5: data.kospiInstitutionTop5,
          ),
        ),
        const SizedBox(height: 20),
        _StaggerReveal(
          delay: const Duration(milliseconds: 180),
          child: Container(
            height: 1,
            color: cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 20),
        _StaggerReveal(
          delay: const Duration(milliseconds: 240),
          child: _InvestorFlowMarketBlock(
            marketLabel: 'KOSDAQ',
            foreignTop5: data.kosdaqForeignTop5,
            institutionTop5: data.kosdaqInstitutionTop5,
          ),
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

class _FmkoreaHotShareSheet extends StatefulWidget {
  const _FmkoreaHotShareSheet({required this.shareCardKey, required this.data});

  final GlobalKey shareCardKey;
  final FmkoreaStockMentionsSnapshot data;

  @override
  State<_FmkoreaHotShareSheet> createState() => _FmkoreaHotShareSheetState();
}

class _FmkoreaHotShareSheetState extends State<_FmkoreaHotShareSheet> {
  bool _sharing = false;

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  Future<void> _captureAndShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      final boundary =
          widget.shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File(
        '${Directory.systemTemp.path}/fmkorea_hot_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '주식저장소 펨코 실시간 HOT 종목',
        sharePositionOrigin: _shareOrigin(),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mentions = widget.data.topMentions.take(10).toList();
    final stamp = widget.data.updatedAt ?? DateTime.now();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          RepaintBoundary(
            key: widget.shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '주식저장소',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        DateFormat('yyyy.MM.dd HH:mm').format(stamp),
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '🔥 펨코 실시간 HOT 종목',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '집계 게시글 ${widget.data.totalPosts}개',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < mentions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text(
                              '${i + 1}',
                              style: GoogleFonts.robotoMono(
                                color: const Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              mentions[i].name.isEmpty
                                  ? mentions[i].ticker
                                  : mentions[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${mentions[i].mentionCount}회',
                            style: GoogleFonts.robotoMono(
                              color: const Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '주식저장소 앱에서 확인해보세요',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _captureAndShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: const Color(
                  0xFF10B981,
                ).withValues(alpha: 0.4),
              ),
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _sharing ? '처리 중...' : '이미지로 공유',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaggerReveal extends StatefulWidget {
  const _StaggerReveal({
    required this.child,
    this.onceKey,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 300),
    this.beginOffset = const Offset(0, 0.02),
    super.key,
  });

  final Widget child;
  final String? onceKey;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _VisibilityTriggered extends StatefulWidget {
  const _VisibilityTriggered({
    required this.enabled,
    required this.childWhenInactive,
    required this.builder,
  });

  final bool enabled;
  final Widget childWhenInactive;
  final Widget Function() builder;

  @override
  State<_VisibilityTriggered> createState() => _VisibilityTriggeredState();
}

class _VisibilityTriggeredState extends State<_VisibilityTriggered> {
  ScrollPosition? _scrollPosition;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOrWatch());
  }

  bool _isVisibleInScrollable() {
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    final viewport = RenderAbstractViewport.of(renderObject);
    final position = Scrollable.maybeOf(context)?.position;
    if (viewport == null || position == null) return true;

    final top = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    final bottom = viewport.getOffsetToReveal(renderObject, 1.0).offset;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    return bottom >= viewTop && top <= viewBottom;
  }

  void _checkOrWatch() {
    if (!mounted || _triggered || !widget.enabled) return;
    if (_isVisibleInScrollable()) {
      setState(() => _triggered = true);
      return;
    }
    _scrollPosition = Scrollable.maybeOf(context)?.position;
    _scrollPosition?.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || _triggered || !widget.enabled) return;
    if (_isVisibleInScrollable()) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = null;
      setState(() => _triggered = true);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder();
    if (_triggered) return widget.builder();
    return widget.childWhenInactive;
  }
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  static final Set<String> _playedOnceKeys = <String>{};
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(curve);
    final onceKey = widget.onceKey;
    if (onceKey != null && _playedOnceKeys.contains(onceKey)) {
      _controller.value = 1.0;
    } else {
      _play();
    }
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) {
      await Future.delayed(widget.delay);
    }
    if (mounted) {
      await _controller.forward();
      final onceKey = widget.onceKey;
      if (onceKey != null) {
        _playedOnceKeys.add(onceKey);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: RepaintBoundary(child: widget.child),
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

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurface.withValues(alpha: 0.25),
            ),
          ],
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  Future<void> _shareInvestorFlowText() async {
    _InvestorFlowSnapshot? data;
    try {
      final query = await FirebaseFirestore.instance
          .collection('market_investor_flow')
          .orderBy('marketDate', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      final doc = query.docs.isNotEmpty ? query.docs.first : null;
      if (doc != null) {
        data = _InvestorFlowSnapshot.fromMap(doc.data());
      }
    } catch (_) {
      // 데이터 없이 공유
    }
    await Share.share(_shareText(data));
  }

  String _shareText(_InvestorFlowSnapshot? data) {
    final lines = <String>[
      '주식저장소 마감수급',
      '',
      '외국인과 기관이 가장 많이 순매수한 종목을 한눈에 확인해보세요.',
    ];
    if (data != null) {
      lines.addAll([
        '',
        '[${data.marketDate}]',
        '외인 순매수 TOP5 (KOSPI): ${_top5Names(data.kospiForeignTop5)}',
        '기관 순매수 TOP5 (KOSPI): ${_top5Names(data.kospiInstitutionTop5)}',
        '외인 순매수 TOP5 (KOSDAQ): ${_top5Names(data.kosdaqForeignTop5)}',
        '기관 순매수 TOP5 (KOSDAQ): ${_top5Names(data.kosdaqInstitutionTop5)}',
      ]);
    }
    lines.addAll(['', 'https://stockstorage-13828.web.app']);
    return lines.join('\n');
  }

  String _top5Names(List<_InvestorFlowItem> items) {
    final names = items
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty && name != '-')
        .take(5)
        .toList();
    if (names.isEmpty) return '-';
    return names.join(', ');
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

      final file = File(
        '${Directory.systemTemp.path}/investor_flow_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '주식저장소 마감수급',
        sharePositionOrigin: _shareOrigin(),
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
    final captureFrame = _showWatermark || _capturing;

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
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              '외국인과 기관이 가장 많이 순매수한 종목',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '공유하기',
            onPressed: _shareInvestorFlowText,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _StaggerReveal(
              delay: const Duration(milliseconds: 40),
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: captureFrame
                      ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
                      : const EdgeInsets.fromLTRB(0, 0, 0, 8),
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
            ),
            const SizedBox(height: 16),
            _StaggerReveal(
              delay: const Duration(milliseconds: 140),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _capturing ? null : _captureAndShare,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _capturing ? '캡처 중...' : '캡처해서 공유하기',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
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

      final file = File(
        '${Directory.systemTemp.path}/fmkorea_index_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '주식저장소 펨코지수',
        sharePositionOrigin: _shareOrigin(),
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
    final captureFrame = _showWatermark || _capturing;

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
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              '게시글 수와 KOSPI 흐름 비교',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: captureFrame
                    ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
                    : const EdgeInsets.fromLTRB(0, 0, 0, 8),
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
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _capturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _capturing ? '캡처 중...' : '캡처해서 공유하기',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                marketLabel,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'TOP5',
              style: GoogleFonts.robotoMono(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InvestorFlowGroup(
          title: '외국인 순매수',
          color: const Color(0xFF3182F6),
          items: foreignTop5,
          icon: Icons.trending_up_rounded,
          emoji: '🌎',
        ),
        const SizedBox(height: 12),
        _InvestorFlowGroup(
          title: '기관 순매수',
          color: const Color(0xFFEA580C),
          items: institutionTop5,
          icon: Icons.account_balance_rounded,
          emoji: '🏦',
        ),
      ],
    );
  }
}

class _InvestorFlowGroup extends StatelessWidget {
  const _InvestorFlowGroup({
    required this.title,
    required this.color,
    required this.items,
    required this.icon,
    this.emoji,
  });

  final String title;
  final Color color;
  final List<_InvestorFlowItem> items;
  final IconData icon;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: emoji != null
                    ? Center(
                        child: Text(
                          emoji!,
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 9),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'TOP5',
                  style: GoogleFonts.robotoMono(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              '데이터가 없습니다.',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.42),
                fontSize: 12,
              ),
            )
          else
            ...List.generate(items.length, (index) {
              final item = items[index];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.amountEokText,
                            style: GoogleFonts.robotoMono(
                              color: cs.onSurface.withValues(alpha: 0.74),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index != items.length - 1)
                    Container(
                      height: 1,
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                ],
              );
            }),
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF3182F6)),
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
                    dateKey: _normalizeDateKey(doc.id),
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
            todayEntry != null &&
                entries.length >= 2 &&
                latest.dateKey == todayKey
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
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
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
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF3182F6,
                          ).withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '일간 게시글',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF3182F6),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFmkoreaCountSummaryCard(
                          context,
                          label: focusedEntry.dateKey == latest.dateKey
                              ? '최근 마감 게시글 수'
                              : '전일 마감 게시글 수',
                          dateKey: focusedEntry.dateKey,
                          count: focusedEntry.count,
                          accentColor: const Color(0xFF3182F6),
                          subtitle: focusedKospiChange == null
                              ? '전일 KOSPI 변동률 집계 전'
                              : '전일 KOSPI ${_formatSignedPercent(focusedKospiChange)}',
                          subtitleColor: focusedKospiChange == null
                              ? null
                              : focusedKospiChange >= 0
                              ? const Color(0xFFF04452)
                              : const Color(0xFF1677FF),
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
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: effectiveInsight.color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '최근 20일 게시글 수 · KOSPI 변동률',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
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
                          height: 188,
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
                  const SizedBox(height: 24),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: cs.onSurface.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '최근 날짜별 게시글 수 · KOSPI 변동률',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
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
                        ...recentEntries.reversed.map((entry) {
                          final isLast = entry == recentEntries.first;
                          return Column(
                            children: [
                              _buildFmkoreaDailyRow(
                                context,
                                entry: entry,
                                kospiChange: kospiSnapshot
                                    ?.sameDayChangeByDate[entry.dateKey],
                                isToday: entry.dateKey == todayKey,
                                isFocused:
                                    entry.dateKey == focusedEntry.dateKey,
                                isWeekend: !entry.isWeekday,
                                updatedAt: entry.updatedAt,
                              ),
                              if (!isLast)
                                Container(
                                  height: 1,
                                  color: cs.onSurface.withValues(alpha: 0.06),
                                ),
                            ],
                          );
                        }),
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
    final targetIndex = entries.indexWhere(
      (entry) => entry.dateKey == target.dateKey,
    );
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
        ? const Color(0xFFF04452)
        : diffRate >= 15
        ? const Color(0xFFFF9500)
        : diffRate >= -10
        ? const Color(0xFF0DC99A)
        : diffRate >= -25
        ? const Color(0xFF3182F6)
        : const Color(0xFF6366F1);

    return _FmkoreaWeekdayInsight(
      average: average,
      diff: diff,
      diffRate: diffRate,
      sampleCount: baseline.length,
      color: color,
    );
  }

  Future<List<(String, double)>> _fetchNaverKospiHistory() async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 365 * 3));
    final fmt = DateFormat('yyyyMMdd');
    final uri = Uri.parse(
      'https://api.finance.naver.com/siseJson.naver'
      '?symbol=KOSPI&requestType=1'
      '&startTime=${fmt.format(start)}&endTime=${fmt.format(end)}&timeframe=day',
    );
    try {
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set('Referer', 'https://finance.naver.com');
      req.headers.set('User-Agent', 'Mozilla/5.0');
      final res = await req.close();
      final body = await res.transform(const SystemEncoding().decoder).join();
      client.close();
      // format: ["YYYYMMDD", open, high, low, close, ...]
      final rows = RegExp(
        r'\["(\d{8})",\s*[\d.]+,\s*[\d.]+,\s*[\d.]+,\s*([\d.]+)',
      ).allMatches(body);
      return rows.map((m) {
        final dateRaw = m.group(1)!;
        final close = double.parse(m.group(2)!);
        final dateKey =
            '${dateRaw.substring(0, 4)}.${dateRaw.substring(4, 6)}.${dateRaw.substring(6, 8)}';
        return (dateKey, close);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<_FmkoreaKospiSnapshot?> _computeKospiSnapshot(
    List<_FmkoreaDailyCount> entries,
  ) async {
    if (entries.isEmpty) return null;

    final naverHistory = await _fetchNaverKospiHistory();
    final history = naverHistory.isNotEmpty
        ? naverHistory
        : (await StockPriceService.fetchHistoryDetailed(
            '^KS11',
            'US',
            range: '3y',
            interval: '1d',
          )).map((e) => (DateFormat('yyyy.MM.dd').format(e.$1), e.$2)).toList();
    if (history.length < 2) return null;

    final countByDate = {
      for (final entry in entries) entry.dateKey: entry.count.toDouble(),
    };
    final sameDayChangeByDate = <String, double>{};
    final xs = <double>[];
    final ys = <double>[];
    final points = <_FmkoreaScatterPoint>[];

    for (var i = 1; i < history.length; i++) {
      final current = history[i];
      final previous = history[i - 1];
      if (previous.$2 == 0) continue;
      final currentKey = current.$1;
      final currentDate = DateFormat('yyyy.MM.dd').parse(currentKey);
      final changeRate = ((current.$2 - previous.$2) / previous.$2) * 100;
      final prevDayKey = DateFormat(
        'yyyy.MM.dd',
      ).format(currentDate.subtract(const Duration(days: 1)));
      final nextDayKey = DateFormat(
        'yyyy.MM.dd',
      ).format(currentDate.add(const Duration(days: 1)));
      final mappedKey = _resolveKospiDateKey(
        countByDate: countByDate,
        currentKey: currentKey,
        prevDayKey: prevDayKey,
        nextDayKey: nextDayKey,
      );
      sameDayChangeByDate[mappedKey] = changeRate;

      final prevKey = _previousWeekdayKey(
        DateFormat('yyyy.MM.dd').parse(mappedKey),
      );
      final postCount = countByDate[prevKey];
      if (postCount == null) continue;
      xs.add(postCount);
      ys.add(changeRate);
      points.add(
        _FmkoreaScatterPoint(x: postCount, y: changeRate, label: currentKey),
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

  String _resolveKospiDateKey({
    required Map<String, double> countByDate,
    required String currentKey,
    required String prevDayKey,
    required String nextDayKey,
  }) {
    if (countByDate.containsKey(currentKey)) return currentKey;
    if (countByDate.containsKey(prevDayKey)) return prevDayKey;
    if (countByDate.containsKey(nextDayKey)) return nextDayKey;
    return currentKey;
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 13,
            fontWeight: FontWeight.w400,
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
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      decoration: BoxDecoration(color: Colors.transparent),
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
              Flexible(
                child: Text(
                  '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: insight.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
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
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFF3182F6).withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
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
                          color: const Color(
                            0xFF0EA5E9,
                          ).withValues(alpha: 0.12),
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
              color: const Color(0xFF3182F6),
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
                onTapDown: (details) => _selectPoint(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragStart: (details) => _selectPoint(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragUpdate: (details) => _selectPoint(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
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
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);
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
              color: const Color(0xFF3182F6),
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

    final barPaint = Paint()
      ..color = const Color(0xFF3182F6).withValues(alpha: 0.35);
    final todayBarPaint = Paint()..color = const Color(0xFF3182F6);
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
      final barHeight = maxCount == 0
          ? 0.0
          : (point.count / maxCount) * (chartHeight * 0.78);
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
        final y =
            topPad + (chartHeight * 0.5) - (normalized * (chartHeight * 0.34));
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
        tp.paint(canvas, Offset(x - tp.width / 2, topPad + chartHeight + 6));
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

String _normalizeDateKey(String raw) {
  final text = raw.trim();
  final match = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(text);
  if (match == null) return text;
  final y = match.group(1)!;
  final m = match.group(2)!.padLeft(2, '0');
  final d = match.group(3)!.padLeft(2, '0');
  return '$y.$m.$d';
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
    if (correlation >= 0.2) return const Color(0xFF0DC99A);
    if (correlation <= -0.2) return const Color(0xFFF04452);
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
                ? const Color(0xFF0DC99A)
                : const Color(0xFFF04452),
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

    final correlation = corr == null || corrSample < 1
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
                            pointColor: const Color(0xFF3182F6),
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
