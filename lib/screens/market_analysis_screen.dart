import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/market_analysis.dart';
import 'package:share_plus/share_plus.dart';
import '../services/deep_link_service.dart';
import '../services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/stock_price_service.dart';
import 'index_detail_screen.dart';
import 'night_futures_chart_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    ('WTI 원유', 'CL=F'),
    ('나스닥100 선물', 'NQ=F'),
    ('VIX 공포지수', '^VIX'),
    ('미 10년 국채금리', '^TNX'),
    // 심리 지표 계산용
    ('미 3개월 국채금리', '^IRX'),
    ('달러 인덱스', 'DX-Y.NYB'),
    ('구리', 'HG=F'),
    ('금', 'GC=F'),
  ];

  static const _indexDescriptions = {
    'KOSPI': '한국 대형주 종합지수',
    'KOSDAQ': '한국 기술·성장주 지수',
    'S&P 500': '미국 500대 기업 지수',
    'NASDAQ': '미국 기술주 중심 지수',
    'USD/KRW': '원달러 환율',
    '나스닥100 선물': '미국 장전 방향성',
  };

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;
  DateTime? _indicesFetchedAt;

  PriceResult? _kospiNightFutures;
  bool _loadingNightFutures = true;
  bool _isHistoricalNightData = false; // 낮 시간대 전날 데이터 여부

  FearAndGreedResult? _fearAndGreed;
  bool _loadingFearAndGreed = true;

  final _sentimentKey = GlobalKey();
  bool _capturing = false;
  bool _showWatermark = false;

  @override
  void initState() {
    super.initState();
    _fetchIndices();
    _fetchFearAndGreed();
    _fetchNightFutures();
  }

  static bool get _isNightSession {
    final h = DateTime.now().toUtc().add(const Duration(hours: 9)).hour;
    return h >= 18 || h < 5;
  }

  Future<void> _fetchNightFutures() async {
    setState(() => _loadingNightFutures = true);

    if (_isNightSession) {
      // 야간 세션: Cloud Function 실시간 → 실패 시 Firestore 최신 데이터로 fallback
      final result = await StockPriceService.fetchKospiNightFutures();
      if (mounted) {
        if (result != null) {
          setState(() {
            _kospiNightFutures = result;
            _isHistoricalNightData = false;
            _loadingNightFutures = false;
          });
        } else {
          // fallback: Firestore 마지막 기록 가격 조회
          try {
            final snap = await FirebaseFirestore.instance
                .collection('night_futures_prices')
                .orderBy('timestamp', descending: true)
                .limit(1)
                .get();
            if (mounted) {
              if (snap.docs.isNotEmpty) {
                final d = snap.docs.first.data();
                setState(() {
                  _kospiNightFutures = PriceResult(
                    price: (d['price'] as num).toDouble(),
                    change: (d['change'] as num).toDouble(),
                    changeRate: (d['changeRate'] as num).toDouble(),
                    currency: 'KRW',
                  );
                  _isHistoricalNightData = true;
                  _loadingNightFutures = false;
                });
              } else {
                setState(() {
                  _kospiNightFutures = null;
                  _loadingNightFutures = false;
                });
              }
            }
          } catch (_) {
            if (mounted) setState(() { _kospiNightFutures = null; _loadingNightFutures = false; });
          }
        }
      }
    } else {
      // 낮 시간: Firestore에서 마지막 기록 가격 조회
      try {
        final snap = await FirebaseFirestore.instance
            .collection('night_futures_prices')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();
        if (mounted) {
          if (snap.docs.isNotEmpty) {
            final d = snap.docs.first.data();
            setState(() {
              _kospiNightFutures = PriceResult(
                price: (d['price'] as num).toDouble(),
                change: (d['change'] as num).toDouble(),
                changeRate: (d['changeRate'] as num).toDouble(),
                currency: 'KRW',
              );
              _isHistoricalNightData = true;
              _loadingNightFutures = false;
            });
          } else {
            setState(() {
              _kospiNightFutures = null;
              _isHistoricalNightData = true;
              _loadingNightFutures = false;
            });
          }
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _kospiNightFutures = null;
            _isHistoricalNightData = true;
            _loadingNightFutures = false;
          });
        }
      }
    }
  }

  Future<void> _fetchIndices() async {
    setState(() => _loadingIndices = true);
    try {
      await Future.wait(
        _indices.map((e) async {
          final result = await StockPriceService.fetchPrice(e.$2, 'US');
          if (mounted) setState(() => _prices[e.$1] = result);
        }),
      );
    } catch (_) {
      // 일부 지수 로드 실패해도 계속 진행
    } finally {
      if (mounted) {
        setState(() {
          _loadingIndices = false;
          _indicesFetchedAt = DateTime.now();
        });
      }
    }
  }

  Future<void> _fetchFearAndGreed() async {
    setState(() => _loadingFearAndGreed = true);
    final result = await StockPriceService.fetchFearAndGreed();
    if (mounted) {
      setState(() {
        _fearAndGreed = result;
        _loadingFearAndGreed = false;
      });
    }
  }

  Future<void> _captureAndShare() async {
    setState(() { _capturing = true; _showWatermark = true; });
    // 워터마크가 렌더링될 때까지 한 프레임 대기
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      final boundary = _sentimentKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sentiment_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📊 주식저장소 시장 심리 지표',
      );
    } finally {
      if (mounted) setState(() { _capturing = false; _showWatermark = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: const Color(0xFF4ADE80),
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: () async {
        await Future.wait([_fetchIndices(), _fetchFearAndGreed(), _fetchNightFutures()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── KOSPI 200 야간선물 (추후 구현) ──
          _buildNightFuturesCard(context),
          const SizedBox(height: 20),

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
              if (_indicesFetchedAt != null && !_loadingIndices)
                Text(
                  '기준 ${DateFormat('HH:mm').format(_indicesFetchedAt!)}',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              const SizedBox(width: 6),
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
            children: [
              _buildIndexCard(context, 'KOSPI'),
              _buildIndexCard(context, 'KOSDAQ'),
              _buildIndexCard(context, 'S&P 500'),
              _buildIndexCard(context, 'NASDAQ'),
              _buildIndexCard(context, 'USD/KRW'),
              _buildIndexCard(context, '나스닥100 선물'),
            ],
          ),
          const SizedBox(height: 10),
          _buildIndexCard(context, 'WTI 원유'),
          const SizedBox(height: 10),
          _buildWeekendNasdaqCard(context),
          const SizedBox(height: 28),

          // ── 시장 심리 지표 섹션 ──
          RepaintBoundary(
            key: _sentimentKey,
            child: Container(
              color: cs.surface,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text('📊 시장 심리 지표',
                            style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          DateFormat('yyyy.MM.dd').format(DateTime.now()),
                          style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.4),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  _buildFearAndGreedCard(context),
                  const SizedBox(height: 10),
                  _buildSentimentCard(
                    context,
                    name: 'VIX 공포지수',
                    symbol: '^VIX',
                    description: '시장 변동성 지수. 20 이상이면 불안감 고조, 30+ 이면 극도의 공포로 역발상 매수 기회 신호',
                    unit: '',
                  ),
                  const SizedBox(height: 10),
                  _buildSentimentCard(
                    context,
                    name: '미 10년 국채금리',
                    symbol: '^TNX',
                    description: '금리 상승 시 성장주·기술주 하락 압박. 4% 이상이면 채권 매력이 주식 대비 높아짐',
                    unit: '%',
                  ),
                  const SizedBox(height: 10),
                  _buildDerivedCard(
                    context,
                    name: '장단기 금리차',
                    description: '미 10년 국채금리에서 3개월 금리를 뺀 값. 음수(역전)이면 과거 경기침체 선행 신호로 주목받음',
                    unit: '%p',
                    getValue: () {
                      final t10 = _prices['미 10년 국채금리']?.price;
                      final t3m = _prices['미 3개월 국채금리']?.price;
                      if (t10 == null || t3m == null) return null;
                      return t10 - t3m;
                    },
                    getChange: () {
                      final t10 = _prices['미 10년 국채금리'];
                      final t3m = _prices['미 3개월 국채금리'];
                      if (t10 == null || t3m == null) return null;
                      final prevSpread = (t10.price - t10.change) - (t3m.price - t3m.change);
                      final currSpread = t10.price - t3m.price;
                      return currSpread - prevSpread;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildDerivedCard(
                    context,
                    name: '구리/금 비율',
                    description: '구리는 경기민감, 금은 안전자산. 비율 상승은 경기 낙관 심리, 하락은 경기침체 우려를 나타냄',
                    unit: '',
                    getValue: () {
                      final copper = _prices['구리']?.price;
                      final gold = _prices['금']?.price;
                      if (copper == null || gold == null || gold == 0) return null;
                      return copper / gold * 1000;
                    },
                    getChange: () {
                      final copper = _prices['구리'];
                      final gold = _prices['금'];
                      if (copper == null || gold == null || gold.price == 0) return null;
                      final prevCopper = copper.price - copper.change;
                      final prevGold = gold.price - gold.change;
                      if (prevGold == 0) return null;
                      final curr = copper.price / gold.price * 1000;
                      final prev = prevCopper / prevGold * 1000;
                      return curr - prev;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildSentimentCard(
                    context,
                    name: '달러 인덱스',
                    symbol: '달러 인덱스',
                    description: '주요 6개국 통화 대비 달러 강세 지수. 상승 시 신흥국·원자재 약세, 달러 약세 시 위험자산 선호 증가',
                    unit: '',
                  ),
                  if (_showWatermark) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: '주식저장소',
                            style: GoogleFonts.inter(
                                color: const Color(0xFF4ADE80),
                                fontSize: 11,
                                fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: ' 앱에서 확인하세요 📈',
                            style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.4),
                                fontSize: 11),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _capturing ? null : _captureAndShare,
              icon: _capturing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF4ADE80)))
                  : const Icon(Icons.camera_alt_outlined,
                      size: 18, color: Color(0xFF4ADE80)),
              label: Text(
                _capturing ? '캡처 중...' : '캡처해서 공유하기',
                style: GoogleFonts.inter(
                    color: const Color(0xFF4ADE80),
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(
                    color: Color(0xFF4ADE80), width: 1.2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 28),

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

  Color _fearAndGreedColor(double score) {
    if (score < 25) return const Color(0xFFEF4444);
    if (score < 45) return const Color(0xFFF97316);
    if (score < 56) return const Color(0xFFEAB308);
    if (score < 75) return const Color(0xFF84CC16);
    return const Color(0xFF4ADE80);
  }

  String _fearAndGreedLabel(String rating) {
    switch (rating.toLowerCase()) {
      case 'extreme fear':
        return '극단적 공포';
      case 'fear':
        return '공포';
      case 'neutral':
        return '중립';
      case 'greed':
        return '탐욕';
      case 'extreme greed':
        return '극단적 탐욕';
      default:
        return rating;
    }
  }

  Widget _buildNightFuturesCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = _kospiNightFutures;
    final isUp = result?.isUp ?? true;
    final priceColor = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NightFuturesChartScreen(
            initialPrice: result?.price ?? 0,
            initialChange: result?.change ?? 0,
            initialChangeRate: result?.changeRate ?? 0,
          ),
        ),
      ),
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4ADE80).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Text(
                'KOSPI 200 야간선물',
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _isNightSession
                      ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                      : cs.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isNightSession && !_isHistoricalNightData
                      ? '● 야간장'
                      : _isNightSession && _isHistoricalNightData
                          ? '최근 기록'
                          : '전날 야간선물',
                  style: GoogleFonts.inter(
                    color: _isNightSession && !_isHistoricalNightData
                        ? const Color(0xFF4ADE80)
                        : cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (_loadingNightFutures)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF4ADE80)),
                )
              else
                GestureDetector(
                  onTap: _fetchNightFutures,
                  child: Icon(Icons.refresh,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.38)),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 가격 + 변동
          if (_loadingNightFutures)
            const SizedBox(
              height: 56,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)),
              ),
            )
          else if (result == null)
            SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  _isNightSession
                      ? '데이터를 불러올 수 없습니다'
                      : '야간장 운영 시간이 아닙니다 (18:00~05:00 KST)',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.38),
                      fontSize: 13),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result.price.toStringAsFixed(2),
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 40,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'pt',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: priceColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                          color: priceColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isUp ? '+' : ''}${result.change.toStringAsFixed(2)}pt',
                      style: GoogleFonts.inter(
                        color: priceColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          if (result != null) ...[
            const SizedBox(height: 10),
            Text(
              '전일 종가 기준 · KRX 야간세션 18:00~05:00 (KST)',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildFearAndGreedCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: _loadingFearAndGreed
          ? const SizedBox(
              height: 80,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)),
              ),
            )
          : _fearAndGreed == null
              ? SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      '데이터 없음',
                      style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.38),
                          fontSize: 13),
                    ),
                  ),
                )
              : _buildFearAndGreedContent(context, _fearAndGreed!, cs),
    );
  }

  Widget _buildFearAndGreedContent(
      BuildContext context, FearAndGreedResult fg, ColorScheme cs) {
    final color = _fearAndGreedColor(fg.score);
    final label = _fearAndGreedLabel(fg.rating);
    final comparisons = [
      ('전일', fg.previousClose),
      ('1주전', fg.previousWeek),
      ('1달전', fg.previousMonth),
      ('1년전', fg.previousYear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Row(
          children: [
            Text('공포탐욕지수',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const Spacer(),
            Text('S&P 500 기준 · CNN',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Share.share(
                '😱 CNN 공포탐욕지수 (S&P 500 기준)\n'
                '━━━━━━━━━━━━━━━━━━\n'
                '현재: ${fg.score.toStringAsFixed(0)} · $label\n\n'
                '전일:  ${fg.previousClose.toStringAsFixed(0)}\n'
                '1주전: ${fg.previousWeek.toStringAsFixed(0)}\n'
                '1달전: ${fg.previousMonth.toStringAsFixed(0)}\n'
                '1년전: ${fg.previousYear.toStringAsFixed(0)}\n'
                '━━━━━━━━━━━━━━━━━━\n'
                '주식저장소 앱에서 시장 심리를 확인하세요 📈',
              ),
              child: Icon(Icons.share_outlined,
                  size: 16, color: cs.onSurface.withValues(alpha: 0.35)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 반원 게이지
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 220,
                height: 115,
                child: CustomPaint(
                  painter: _SemicircleGaugePainter(
                    score: fg.score,
                    trackColor: cs.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fg.score.toStringAsFixed(0),
                style: GoogleFonts.inter(
                    color: color,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    height: 1),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: GoogleFonts.inter(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 구간 라벨
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('극도 공포',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.3),
                      fontSize: 10)),
              Text('극도 탐욕',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.3),
                      fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 비교 칩
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: comparisons.map((c) {
            final prev = c.$2;
            final isUp = fg.score >= prev;
            final chipColor = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(c.$1,
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(
                      '${isUp ? '▲' : '▼'} ${prev.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                          color: chipColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSentimentCard(BuildContext context, {
    required String name,
    required String symbol,
    required String description,
    required String unit,
  }) {
    final cs = Theme.of(context).colorScheme;
    final result = _prices[name];
    final isUp = result?.isUp ?? true;
    final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 이름 + 현재값
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(name,
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const Spacer(),
              if (_loadingIndices)
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF4ADE80)))
              else if (result == null)
                Text('--', style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.38), fontSize: 18))
              else
                Text(
                  '${result.price.toStringAsFixed(2)}$unit',
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 하단: 설명 + 변화량 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(description,
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                        height: 1.5)),
              ),
              if (result != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('전일 대비',
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 10)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDerivedCard(BuildContext context, {
    required String name,
    required String description,
    required String unit,
    required double? Function() getValue,
    required double? Function() getChange,
  }) {
    final cs = Theme.of(context).colorScheme;
    final value = getValue();
    final change = getChange();
    final changeIsUp = change != null && change >= 0;
    final changeColor = changeIsUp ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 이름 + 현재값
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(name,
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const Spacer(),
              if (_loadingIndices)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF4ADE80)))
              else if (value == null)
                Text('--',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.38),
                        fontSize: 18))
              else
                Text(
                  '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}$unit',
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 하단: 설명 + 변화량 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(description,
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                        height: 1.5)),
              ),
              if (value != null && change != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${changeIsUp ? '+' : ''}${change.toStringAsFixed(2)}$unit',
                        style: GoogleFonts.inter(
                            color: changeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('전일 대비',
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 10)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekendNasdaqCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final html = '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{margin:0;background:${isDark ? '#1A2035' : '#ffffff'};}</style>
</head><body>
<div class="tradingview-widget-container" style="height:220px;width:100%">
  <div class="tradingview-widget-container__widget"></div>
  <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-mini-symbol-overview.js" async>
  {
    "symbol": "CAPITALCOM:US100",
    "width": "100%",
    "height": 220,
    "locale": "kr",
    "dateRange": "1D",
    "colorTheme": "${isDark ? 'dark' : 'light'}",
    "isTransparent": true,
    "autosize": true,
    "largeChartUrl": ""
  }
  </script>
</div>
</body></html>''';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(cs.surface)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) => req.isMainFrame && req.url != 'about:blank'
            ? NavigationDecision.prevent
            : NavigationDecision.navigate,
      ))
      ..loadHtmlString(html);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Text('위캔드 나스닥',
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('주말 포함',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4ADE80),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: WebViewWidget(controller: controller),
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
                color: cs.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w600),
          ),
          if (_indexDescriptions[name] != null)
            Text(
              _indexDescriptions[name]!,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 9),
              overflow: TextOverflow.ellipsis,
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
                Row(
                  children: [
                    Text(
                      DateFormat('yyyy년 MM월 dd일').format(a.createdAt),
                      style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.38), fontSize: 12),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Share.share(
                        '📊 주식저장소 시황 분석\n'
                        '━━━━━━━━━━━━━━━━━━\n'
                        '${a.title}\n\n'
                        '${a.body.length > 100 ? '${a.body.substring(0, 100)}...' : a.body}\n'
                        '━━━━━━━━━━━━━━━━━━\n'
                        '👉 ${DeepLinkService.analysisUrl(a)}',
                      ),
                      child: Icon(Icons.share_outlined,
                          size: 20, color: cs.onSurface.withValues(alpha: 0.45)),
                    ),
                  ],
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

class _SemicircleGaugePainter extends CustomPainter {
  final double score;
  final Color trackColor;

  const _SemicircleGaugePainter({
    required this.score,
    required this.trackColor,
  });

  static const _segments = [
    (0.0,  0.25, Color(0xFFEF4444)),
    (0.25, 0.45, Color(0xFFF97316)),
    (0.45, 0.55, Color(0xFFEAB308)),
    (0.55, 0.75, Color(0xFF84CC16)),
    (0.75, 1.0,  Color(0xFF4ADE80)),
  ];

  Color get _needleColor {
    for (final s in _segments) {
      if (score / 100 <= s.$2) return s.$3;
    }
    return _segments.last.$3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;          // 바닥에 중심
    final radius = size.width * 0.44;
    const strokeWidth = 14.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // 트랙 (전체 반원)
    canvas.drawArc(
      rect, startAngle, sweepAngle, false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt,
    );

    // 구간별 색상 아크 (score까지만)
    final pct = (score / 100).clamp(0.0, 1.0);
    for (final seg in _segments) {
      final segStart = seg.$1;
      final segEnd = seg.$2;
      final segColor = seg.$3;
      if (pct <= segStart) break;
      final drawEnd = pct < segEnd ? pct : segEnd;
      canvas.drawArc(
        rect,
        startAngle + sweepAngle * segStart,
        sweepAngle * (drawEnd - segStart),
        false,
        Paint()
          ..color = segColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }

    // 바늘
    final needleAngle = startAngle + sweepAngle * pct;
    final needleLen = radius - strokeWidth - 4;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + needleLen * math.cos(needleAngle),
             cy + needleLen * math.sin(needleAngle)),
      Paint()
        ..color = _needleColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 중심 원
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = _needleColor);
  }

  @override
  bool shouldRepaint(_SemicircleGaugePainter old) => old.score != score;
}
