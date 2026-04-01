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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildTopTabBar(context),
          ),
          const SizedBox(height: 14),
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
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.surface, cs.surface.withValues(alpha: 0.96)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF4ADE80), Color(0xFF22C55E)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(16),
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
          Tab(text: '지표'),
          Tab(text: '시황분석'),
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
          _buildSentimentEntryCard(context),
          const SizedBox(height: 16),
          _buildIndicesPanel(context),
          const SizedBox(height: 16),
          const _InvestorFlowCard(),
          const SizedBox(height: 16),
          const _FmkoreaIndexCard(),
        ],
      ),
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
                      '주요 지표',
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _indicesFetchedAt == null
                          ? '핵심 시장 지표를 빠르게 확인하세요'
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4ADE80).withValues(alpha: 0.14),
                  const Color(0xFFF59E0B).withValues(alpha: 0.12),
                ],
              ),
            ),
            child: Row(
              children: [
                _buildMiniPulse(
                  label: '국내',
                  primary: _prices['KOSPI'],
                  secondary: _prices['KOSDAQ'],
                ),
                const SizedBox(width: 10),
                _buildMiniPulse(
                  label: '미국',
                  primary: _prices['S&P 500'],
                  secondary: _prices['NASDAQ'],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _indices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.24,
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

  Widget _buildMiniPulse({
    required String label,
    required PriceResult? primary,
    required PriceResult? secondary,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: const Color(0xFF0F172A).withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _buildMiniPulseLine(primary),
            const SizedBox(height: 6),
            _buildMiniPulseLine(secondary),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPulseLine(PriceResult? result) {
    final isUp = result?.isUp ?? true;
    final color = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            result == null
                ? '데이터 없음'
                : '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndexCard(BuildContext context, String name, String symbol) {
    final cs = Theme.of(context).colorScheme;
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
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.12), cs.surface],
          ),
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
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.36),
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
                    vertical: 6,
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
                    cs.surface,
                    const Color(0xFF4ADE80).withValues(alpha: 0.09),
                  ],
                ),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    '매일 쌓이는 시황 분석 글을 카드형으로 정리했습니다. 글을 누르면 상세 페이지에서 더 편하게 읽을 수 있습니다.',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.55,
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

  Widget _buildAnalysisCard(BuildContext context, MarketAnalysis analysis) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = analysis.imageUrls.isNotEmpty;
    final preview = analysis.body.replaceAll('\n', ' ').trim();

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
                          Text(
                            hasImage ? '이미지 포함' : '텍스트 중심',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.38),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '자세히 보기',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF16A34A),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
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
                        const Color(0xFF4ADE80).withValues(alpha: 0.18),
                        const Color(0xFFF59E0B).withValues(alpha: 0.16),
                      ],
                    ),
                  ),
                  child: Icon(
                    hasImage ? Icons.article_outlined : Icons.subject_rounded,
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
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

        final chartEntries = entries.length > 14
            ? entries.sublist(entries.length - 14)
            : entries;
        final latest = chartEntries.last;
        final previous = chartEntries.length >= 2
            ? chartEntries[chartEntries.length - 2]
            : null;
        final diff = previous == null ? 0 : latest.count - previous.count;
        final diffRate = previous == null || previous.count == 0
            ? 0.0
            : (diff / previous.count) * 100;
        final maxCount = chartEntries
            .map((entry) => entry.count)
            .fold<int>(1, (acc, value) => value > acc ? value : acc);
        final trendColor = diff >= 0
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);
        final updatedAt = entries
            .map((entry) => entry.updatedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (acc, item) {
              if (acc == null) return item;
              return item.isAfter(acc) ? item : acc;
            });

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
                      '일별 게시글',
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
                'FM코리아 주식 게시판의 일별 게시글 수 흐름입니다.',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
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
                            latest.dateKey,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.46),
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
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
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
                          Text(
                            previous == null
                                ? '비교 데이터가 아직 부족합니다.'
                                : '전일 대비 ${diff >= 0 ? '+' : ''}$diff건 · ${diffRate.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              color: trendColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 92,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(
                          previous == null
                              ? '-'
                              : '${diff >= 0 ? '+' : ''}${diffRate.toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                            color: trendColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '전일 대비',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.42),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
}
