import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';

class StockAiAnalysisResultScreen extends StatefulWidget {
  final StockPick pick;
  final PriceResult? price;
  final FundamentalsResult? fundamentals;
  final List<Map<String, dynamic>> candles;
  final List<StockNews> news;

  const StockAiAnalysisResultScreen({
    super.key,
    required this.pick,
    this.price,
    this.fundamentals,
    this.candles = const [],
    this.news = const [],
  });

  @override
  State<StockAiAnalysisResultScreen> createState() =>
      _StockAiAnalysisResultScreenState();

  static String cleanText(String value) {
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

  static String cleanSummaryText(String value) {
    var text = cleanText(value);
    final match = RegExp(
      r',?\s*"(theme|sector|todayReason|fundamentals|technical|news|momentum|risks|sections)"\s*:',
    ).firstMatch(text);
    if (match != null && match.start > 0) {
      text = text.substring(0, match.start);
    }
    return cleanText(text);
  }

  static String joinText(List<String> values) {
    return values.map(cleanText).where((v) => v.isNotEmpty).join('\n\n');
  }
}

class _StockAiAnalysisResultScreenState
    extends State<StockAiAnalysisResultScreen> {
  final _firestore = FirestoreService();
  Timer? _timer;
  StockAiAnalysisResult? _analysis;
  _AiTechnicalMetrics? _technicalMetrics;
  bool _loading = true;
  bool _fromCache = false;
  int _elapsedSeconds = 0;
  String? _error;

  static const _loadingMessages = [
    '개인 기록에서 기존 분석을 확인하는 중',
    '최근 뉴스와 당일 흐름을 정리하는 중',
    'PER, PBR, BPS 같은 밸류 지표를 맞춰보는 중',
    '캔들, 이동평균, 지지·저항 구간을 읽는 중',
    '모멘텀과 리스크를 카드로 나누는 중',
  ];

  String get _analysisId =>
      FirestoreService.favoriteStockKey(widget.pick.market, widget.pick.ticker);

  @override
  void initState() {
    super.initState();
    _loadOrGenerate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _loadOrGenerate({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = '로그인 후 AI 분석을 사용할 수 있습니다.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
    });
    _startTimer();

    try {
      final candles = await _analysisCandles();
      final metrics = _AiTechnicalMetrics.fromCandles(candles);

      if (!forceRefresh) {
        final cached = await _firestore.getStockAiAnalysis(
          user.uid,
          _analysisId,
        );
        if (cached != null) {
          if (!mounted) return;
          _stopTimer();
          setState(() {
            _analysis = cached;
            _technicalMetrics = metrics;
            _fromCache = true;
            _loading = false;
          });
          return;
        }
      }

      final result = await StockPriceService.generateStockAiAnalysis(
        ticker: widget.pick.ticker,
        name: widget.pick.name,
        market: widget.pick.market,
        price: widget.price,
        fundamentals: widget.fundamentals,
        candles: candles,
        news: widget.news,
      );
      await _firestore.saveStockAiAnalysis(
        user.uid,
        _analysisId,
        result,
        pick: widget.pick,
      );
      if (!mounted) return;
      _stopTimer();
      setState(() {
        _analysis = result;
        _technicalMetrics = metrics;
        _fromCache = false;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('AI analysis load failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      _stopTimer();
      setState(() {
        _loading = false;
        _error = 'AI 분석을 불러오지 못했습니다.\n${e.toString()}';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _analysisCandles() async {
    if (widget.candles.length >= 80) return widget.candles;
    final dailyCandles = await StockPriceService.fetchOHLC(
      widget.pick.ticker,
      widget.pick.market,
      interval: '1d',
      range: '2y',
    );
    if (dailyCandles.isEmpty) return widget.candles;
    final start = max(0, dailyCandles.length - 140);
    return dailyCandles
        .skip(start)
        .map(
          (c) => {
            'date': DateFormat('yyyy-MM-dd').format(c.date),
            'open': c.open,
            'high': c.high,
            'low': c.low,
            'close': c.close,
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        actions: [
          if (!_loading && _analysis != null)
            IconButton(
              tooltip: '새로 분석',
              icon: Icon(Icons.refresh, color: cs.onSurface),
              onPressed: () => _loadOrGenerate(forceRefresh: true),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      final message =
          _loadingMessages[(_elapsedSeconds ~/ 3) % _loadingMessages.length];
      return _LoadingAnalysisView(
        pick: widget.pick,
        elapsedSeconds: _elapsedSeconds,
        message: message,
      );
    }

    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: () => _loadOrGenerate());
    }

    final analysis = _analysis;
    if (analysis == null) {
      return _ErrorView(
        error: '표시할 AI 분석 결과가 없습니다.',
        onRetry: () => _loadOrGenerate(forceRefresh: true),
      );
    }

    return _AnalysisContent(
      pick: widget.pick,
      analysis: analysis,
      price: widget.price,
      fundamentals: widget.fundamentals,
      fromCache: _fromCache,
      technicalMetrics: _technicalMetrics,
    );
  }
}

class _LoadingAnalysisView extends StatelessWidget {
  final StockPick pick;
  final int elapsedSeconds;
  final String message;

  const _LoadingAnalysisView({
    required this.pick,
    required this.elapsedSeconds,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = ((elapsedSeconds % 24) + 1) / 24;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_outlined,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pick.name,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$elapsedSeconds초째 분석 중',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.48),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  color: const Color(0xFF10B981),
                  backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.78),
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '처음 한 번만 생성하면 이후에는 개인 기록에서 바로 불러옵니다.',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.42),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _LoadingChecklist(elapsedSeconds: elapsedSeconds),
      ],
    );
  }
}

class _LoadingChecklist extends StatelessWidget {
  final int elapsedSeconds;

  const _LoadingChecklist({required this.elapsedSeconds});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      ('기존 분석 기록 확인', elapsedSeconds >= 1),
      ('뉴스·당일 등락 원인 요약', elapsedSeconds >= 4),
      ('재무·밸류에이션 점검', elapsedSeconds >= 7),
      ('차트·기술 지표 해석', elapsedSeconds >= 10),
      ('점수·리스크 정리', elapsedSeconds >= 13),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      item.$2
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: item.$2
                          ? const Color(0xFF10B981)
                          : cs.onSurface.withValues(alpha: 0.24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.$1,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.66),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle(
                icon: Icons.error_outline,
                title: '분석 실패',
                color: Color(0xFFF04452),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalysisContent extends StatelessWidget {
  final StockPick pick;
  final StockAiAnalysisResult analysis;
  final PriceResult? price;
  final FundamentalsResult? fundamentals;
  final bool fromCache;
  final _AiTechnicalMetrics? technicalMetrics;

  const _AnalysisContent({
    required this.pick,
    required this.analysis,
    required this.price,
    required this.fundamentals,
    required this.fromCache,
    required this.technicalMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final generatedText = analysis.generatedAt == null
        ? null
        : DateFormat('yyyy.MM.dd HH:mm').format(analysis.generatedAt!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _ReportHeroCard(pick: pick, price: price, analysis: analysis),
        const SizedBox(height: 12),
        _SnapshotGrid(
          analysis: analysis,
          price: price,
          fundamentals: fundamentals,
          technicalMetrics: technicalMetrics,
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          text: StockAiAnalysisResultScreen.cleanSummaryText(analysis.summary),
        ),
        const SizedBox(height: 12),
        _SignalGridCard(analysis: analysis),
        const SizedBox(height: 12),
        _SourceEvidenceCard(analysis: analysis),
        const SizedBox(height: 12),
        _DataRoomCard(
          fundamentals: fundamentals,
          analysis: analysis,
          technicalMetrics: technicalMetrics,
        ),
        const SizedBox(height: 12),
        _ScoreBoardCard(analysis: analysis, fundamentals: fundamentals),
        const SizedBox(height: 12),
        _StatusCard(fromCache: fromCache, generatedText: generatedText),
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
    );
  }
}

class _ReportHeroCard extends StatelessWidget {
  final StockPick pick;
  final PriceResult? price;
  final StockAiAnalysisResult analysis;

  const _ReportHeroCard({
    required this.pick,
    required this.price,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = analysis.score;
    final scoreColor = _scoreColor(score);
    final scoreValue = score?.round();
    final scoreText = scoreValue == null ? '--' : scoreValue.toString();
    final scoreCaption = scoreValue == null
        ? '분석 대기'
        : scoreValue >= 75
        ? '우호적'
        : scoreValue >= 55
        ? '중립'
        : '주의';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18B6A4), Color(0xFF109178)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF109178).withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _MarketPill(market: pick.market, inverse: true),
                        const SizedBox(width: 7),
                        Text(
                          pick.ticker,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      pick.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      analysis.scoreLabel.isEmpty
                          ? 'AI가 뉴스, 재무, 차트 흐름을 종합했습니다.'
                          : _cleanScoreLabel(analysis.scoreLabel, scoreValue),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI SCORE',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.42),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      scoreText,
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: score == null ? 0 : score.clamp(0, 100) / 100,
                        minHeight: 6,
                        color: scoreColor,
                        backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      scoreCaption,
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: '현재가',
                    value: price?.formattedPrice ?? '-',
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                Expanded(
                  child: _HeroStat(
                    label: '등락',
                    value: _formatHeroChange(price),
                    alignEnd: true,
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

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _HeroStat({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SnapshotGrid extends StatelessWidget {
  final StockAiAnalysisResult analysis;
  final PriceResult? price;
  final FundamentalsResult? fundamentals;
  final _AiTechnicalMetrics? technicalMetrics;

  const _SnapshotGrid({
    required this.analysis,
    required this.price,
    required this.fundamentals,
    required this.technicalMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _SnapshotItem(
        label: 'RSI',
        value: technicalMetrics?.rsi14 == null
            ? '-'
            : technicalMetrics!.rsi14!.toStringAsFixed(1),
        caption: _rsiVerdict(technicalMetrics?.rsi14),
        icon: Icons.speed_outlined,
      ),
      _SnapshotItem(
        label: '20일 수익률',
        value: _formatPercent(technicalMetrics?.return20),
        caption: _returnVerdict(technicalMetrics?.return20),
        icon: Icons.timeline_outlined,
      ),
      _SnapshotItem(
        label: 'PER',
        value: fundamentals?.per == null
            ? '-'
            : fundamentals!.per!.toStringAsFixed(1),
        caption: _peerPerCaption(analysis),
        icon: Icons.request_quote_outlined,
      ),
      _SnapshotItem(
        label: 'PBR',
        value: fundamentals?.pbr == null
            ? '-'
            : fundamentals!.pbr!.toStringAsFixed(2),
        caption: _valuationVerdict(fundamentals?.pbr, lowGood: true),
        icon: Icons.account_balance_outlined,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 86,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (_, index) => _SnapshotTile(item: items[index]),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  final _SnapshotItem item;

  const _SnapshotTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _verdictColor(item.caption);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(item.icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.48),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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

class _SnapshotItem {
  final String label;
  final String value;
  final String caption;
  final IconData icon;

  const _SnapshotItem({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
  });
}

class _ScoreBoardCard extends StatelessWidget {
  final StockAiAnalysisResult analysis;
  final FundamentalsResult? fundamentals;

  const _ScoreBoardCard({required this.analysis, required this.fundamentals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = analysis.score ?? 50;
    final items = [
      _ScoreItem(
        label: '뉴스',
        value: _scoreFromText(analysis.news, base),
        icon: Icons.article_outlined,
      ),
      _ScoreItem(
        label: '차트',
        value: _scoreFromText(analysis.technical, base),
        icon: Icons.show_chart,
      ),
      _ScoreItem(
        label: '재무',
        value: _fundamentalScore(fundamentals, base),
        icon: Icons.account_balance_outlined,
      ),
      _ScoreItem(
        label: '모멘텀',
        value: _scoreFromText(analysis.momentum, base),
        icon: Icons.bolt_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.dashboard_customize_outlined,
            title: '점수 구성',
            color: Color(0xFF1677FF),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => _ScoreTile(item: item)),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final _ScoreItem item;

  const _ScoreTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _scoreColor(item.value);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: color, size: 18),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              item.label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.66),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: item.value.clamp(0, 100) / 100,
                minHeight: 8,
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.value.round().toString(),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalGridCard extends StatelessWidget {
  final StockAiAnalysisResult analysis;

  const _SignalGridCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final signals = [
      _SignalItem(
        title: '당일 재료',
        value: _signalLabel(analysis.todayReason),
        body: analysis.todayReason,
        icon: Icons.flash_on_outlined,
      ),
      _SignalItem(
        title: '테마 적합도',
        value: _signalLabel(analysis.theme),
        body: _themeDisplayText(analysis.theme),
        icon: Icons.hub_outlined,
      ),
      _SignalItem(
        title: '뉴스 방향',
        value: _signalLabel(analysis.news),
        body: _newsDisplayText(analysis),
        icon: Icons.feed_outlined,
      ),
      _SignalItem(
        title: '리스크',
        value: analysis.risks.isEmpty ? '낮음' : '${analysis.risks.length}개',
        body: analysis.risks.take(2).join(' / '),
        icon: Icons.report_gmailerrorred_outlined,
        danger: analysis.risks.length >= 3,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.fact_check_outlined,
            title: '핵심 포인트',
            color: Color(0xFF10B981),
          ),
          const SizedBox(height: 12),
          ...signals.map((signal) => _SignalRow(signal: signal)),
          _ThemePeersCard(peers: analysis.themePeers),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  final _SignalItem signal;

  const _SignalRow({required this.signal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = signal.danger
        ? const Color(0xFFF04452)
        : _signalColor(signal.value);
    final body = StockAiAnalysisResultScreen.cleanText(signal.body);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(signal.icon, color: color, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  signal.title,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.52),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                signal.value,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (body.isEmpty || body == '-')
            Text(
              '확인 가능한 근거가 부족합니다.',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.46),
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _readableLines(body)
                  .take(3)
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 8, right: 8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.68),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.70),
                                fontSize: 12.5,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ThemePeersCard extends StatelessWidget {
  final List<String> peers;

  const _ThemePeersCard({required this.peers});

  @override
  Widget build(BuildContext context) {
    final cleaned = peers
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .take(8)
        .toList();
    if (cleaned.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    const color = Color(0xFF14B8A6);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_outlined, color: color, size: 17),
              const SizedBox(width: 6),
              Text(
                '같은 테마 종목',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: cleaned
                .map(
                  (peer) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color.withValues(alpha: 0.16)),
                    ),
                    child: Text(
                      peer,
                      style: const TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SourceEvidenceCard extends StatelessWidget {
  final StockAiAnalysisResult analysis;

  const _SourceEvidenceCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasNews = analysis.sourceNews.isNotEmpty;
    final hasDisclosures = analysis.sourceDisclosures.isNotEmpty;
    final hasFinancials = analysis.sourceFinancials.isNotEmpty;
    if (!hasNews && !hasDisclosures && !hasFinancials) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.verified_outlined,
            title: '공시 · 뉴스 · 재무',
            color: Color(0xFF1677FF),
          ),
          if (hasDisclosures) ...[
            const SizedBox(height: 12),
            _SourceGroup(
              title: '최근 공시',
              icon: Icons.description_outlined,
              color: const Color(0xFF6366F1),
              children: analysis.sourceDisclosures
                  .take(5)
                  .map(
                    (item) => _SourceLine(
                      title: item.title,
                      meta: [
                        _formatDartDate(item.date),
                        if (item.submitter.isNotEmpty) item.submitter,
                        if (item.receiptNo.isNotEmpty) '접수 ${item.receiptNo}',
                      ].where((v) => v.isNotEmpty).join(' · '),
                      url: item.url.isNotEmpty
                          ? item.url
                          : _dartDisclosureUrl(item.receiptNo),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (hasNews) ...[
            const SizedBox(height: 12),
            _SourceGroup(
              title: '최근 뉴스',
              icon: Icons.article_outlined,
              color: const Color(0xFF14B8A6),
              children: analysis.sourceNews
                  .take(5)
                  .map(
                    (item) => _SourceLine(
                      title: item.title,
                      meta: [
                        if (item.publisher.isNotEmpty) item.publisher,
                        _formatSourceDate(item.publishedAt),
                      ].where((v) => v.isNotEmpty).join(' · '),
                      url: item.url,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (hasFinancials) ...[
            const SizedBox(height: 12),
            _SourceGroup(
              title: '최근 재무',
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFFF59E0B),
              children: analysis.sourceFinancials
                  .take(6)
                  .map(
                    (item) => _SourceLine(
                      title:
                          '${item.account}: ${_formatFinancialAmountToEok(item.current)}',
                      meta: [
                        if (item.previous.isNotEmpty)
                          '전기 ${_formatFinancialAmountToEok(item.previous)}',
                        if (item.statement.isNotEmpty) item.statement,
                      ].join(' · '),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _SourceGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _SourceLine extends StatelessWidget {
  final String title;
  final String meta;
  final String url;

  const _SourceLine({required this.title, required this.meta, this.url = ''});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(url);
    final canOpen = uri != null && uri.hasScheme;
    final content = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.82),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (canOpen) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.38),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
    if (!canOpen) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: content,
    );
  }
}

class _ResolvedFundamentals {
  final double? per;
  final double? pbr;
  final double? bps;
  final double? eps;
  final int? marketCap;

  const _ResolvedFundamentals({
    required this.per,
    required this.pbr,
    required this.bps,
    required this.eps,
    required this.marketCap,
  });

  factory _ResolvedFundamentals.from(
    FundamentalsResult? fundamentals,
    StockAiAnalysisResult analysis,
  ) {
    return _ResolvedFundamentals(
      per: fundamentals?.per,
      pbr: fundamentals?.pbr,
      bps: fundamentals?.bps,
      eps: analysis.sourceEps,
      marketCap:
          fundamentals?.marketCap ??
          analysis.sourceMarketCap ??
          _marketCapFromAnalysis(analysis),
    );
  }
}

class _DataRoomCard extends StatelessWidget {
  final FundamentalsResult? fundamentals;
  final StockAiAnalysisResult analysis;
  final _AiTechnicalMetrics? technicalMetrics;

  const _DataRoomCard({
    required this.fundamentals,
    required this.analysis,
    required this.technicalMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = _ResolvedFundamentals.from(fundamentals, analysis);
    final rows = [
      _MetricRowData(
        label: 'PER',
        value: resolved.per == null ? '-' : resolved.per!.toStringAsFixed(1),
        verdict: _peerPerCaption(analysis),
      ),
      _MetricRowData(
        label: 'PBR',
        value: resolved.pbr == null ? '-' : resolved.pbr!.toStringAsFixed(2),
        verdict: _valuationVerdict(resolved.pbr, lowGood: true),
      ),
      _MetricRowData(
        label: 'BPS',
        value: resolved.bps == null
            ? '-'
            : NumberFormat('#,###').format(resolved.bps),
        verdict: resolved.bps == null ? '데이터 없음' : '1주당 순자산',
      ),
      _MetricRowData(
        label: 'EPS',
        value: resolved.eps == null
            ? '-'
            : NumberFormat('#,###').format(resolved.eps),
        verdict: resolved.eps == null ? '데이터 없음' : '1주당 순이익',
      ),
      _MetricRowData(
        label: '시가총액',
        value: resolved.marketCap == null
            ? '-'
            : _formatMarketCap(resolved.marketCap!),
        verdict: resolved.marketCap == null ? '데이터 없음' : '기업 가치 규모',
      ),
      _MetricRowData(
        label: 'RSI 14',
        value: technicalMetrics?.rsi14 == null
            ? '-'
            : technicalMetrics!.rsi14!.toStringAsFixed(1),
        verdict: _rsiVerdict(technicalMetrics?.rsi14),
      ),
      _MetricRowData(
        label: '5일 수익률',
        value: _formatPercent(technicalMetrics?.return5),
        verdict: _returnVerdict(technicalMetrics?.return5),
      ),
      _MetricRowData(
        label: '20일 수익률',
        value: _formatPercent(technicalMetrics?.return20),
        verdict: _returnVerdict(technicalMetrics?.return20),
      ),
      _MetricRowData(
        label: '60일 수익률',
        value: _formatPercent(technicalMetrics?.return60),
        verdict: _returnVerdict(technicalMetrics?.return60),
      ),
      _MetricRowData(
        label: '120일 수익률',
        value: _formatPercent(technicalMetrics?.return120),
        verdict: _returnVerdict(technicalMetrics?.return120),
      ),
      _MetricRowData(
        label: '볼린저 위치',
        value: technicalMetrics?.bollingerPosition ?? '-',
        verdict: technicalMetrics?.bollingerVerdict ?? '데이터 없음',
      ),
      _MetricRowData(
        label: '외국인 2주',
        value: _formatShareFlow(analysis.sourceDailyInvestorFlow?.foreignNet14),
        verdict: _shareFlowVerdict(
          analysis.sourceDailyInvestorFlow?.foreignNet14,
        ),
      ),
      _MetricRowData(
        label: '기관 2주',
        value: _formatShareFlow(
          analysis.sourceDailyInvestorFlow?.institutionNet14,
        ),
        verdict: _shareFlowVerdict(
          analysis.sourceDailyInvestorFlow?.institutionNet14,
        ),
      ),
      _MetricRowData(
        label: '외국인 보유율',
        value: analysis.sourceDailyInvestorFlow?.latestForeignHoldRate == null
            ? '-'
            : '${analysis.sourceDailyInvestorFlow!.latestForeignHoldRate!.toStringAsFixed(2)}%',
        verdict: analysis.sourceDailyInvestorFlow?.latestForeignHoldRate == null
            ? '데이터 없음'
            : '최근 기준',
      ),
    ];
    final valuationRows = rows.take(5).toList();
    final technicalRows = rows.skip(5).take(6).toList();
    final flowRows = rows.skip(11).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.format_list_bulleted_outlined,
            title: '데이터 보드',
            color: Color(0xFF14B8A6),
          ),
          const SizedBox(height: 12),
          _DataGroup(title: '밸류에이션', rows: valuationRows),
          _DataGroup(
            title: '기술 지표',
            rows: technicalRows,
            footer: _MovingAveragePositionCard(metrics: technicalMetrics),
          ),
          _DataGroup(
            title: '수급',
            rows: flowRows,
            footer: _InvestorFlowTable(flow: analysis.sourceDailyInvestorFlow),
          ),
        ],
      ),
    );
  }
}

class _DataGroup extends StatelessWidget {
  final String title;
  final List<_MetricRowData> rows;
  final Widget? footer;

  const _DataGroup({required this.title, required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: title == '밸류에이션',
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          iconColor: const Color(0xFF14B8A6),
          collapsedIconColor: cs.onSurface.withValues(alpha: 0.42),
          title: Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          children: [
            ...rows.map((row) => _MetricRow(row: row)),
            ?footer,
          ],
        ),
      ),
    );
  }
}

class _InvestorFlowTable extends StatelessWidget {
  final StockAiDailyInvestorFlow? flow;

  const _InvestorFlowTable({required this.flow});

  @override
  Widget build(BuildContext context) {
    final days = flow?.days ?? const <StockAiInvestorFlowDay>[];
    if (days.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '최근 ${days.length}거래일 일별 수급',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '순매매량 기준',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.48),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _InvestorFlowTableRow(
            date: '날짜',
            foreign: '외국인',
            institution: '기관',
            rate: '등락률',
            header: true,
          ),
          ...days
              .take(14)
              .map(
                (day) => _InvestorFlowTableRow(
                  date: _shortDate(day.date),
                  foreign: _formatShareFlow(day.foreignNet),
                  institution: _formatShareFlow(day.institutionNet),
                  rate: day.changeRate == null
                      ? '-'
                      : '${day.changeRate! > 0 ? '+' : ''}${day.changeRate!.toStringAsFixed(2)}%',
                  foreignPositive: (day.foreignNet ?? 0) > 0,
                  institutionPositive: (day.institutionNet ?? 0) > 0,
                  ratePositive: (day.changeRate ?? 0) > 0,
                ),
              ),
        ],
      ),
    );
  }
}

class _MovingAveragePositionCard extends StatelessWidget {
  final _AiTechnicalMetrics? metrics;

  const _MovingAveragePositionCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final close = metrics?.latestClose;
    final lines = [
      _MaLineData(label: '5일', value: metrics?.ma5),
      _MaLineData(label: '20일', value: metrics?.ma20),
      _MaLineData(label: '60일', value: metrics?.ma60),
      _MaLineData(label: '120일', value: metrics?.ma120),
    ].where((line) => line.value != null && line.value! > 0).toList();
    if (close == null || lines.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final values = [close, ...lines.map((line) => line.value!)];
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final spread = max(maxValue - minValue, close * 0.012);
    final low = minValue - spread * 0.16;
    final high = maxValue + spread * 0.16;
    double pos(double value) => ((value - low) / (high - low)).clamp(0.0, 1.0);

    final aboveCount = lines.where((line) => close >= line.value!).length;
    final headline = aboveCount == lines.length
        ? '주요 이동평균선 위'
        : aboveCount == 0
        ? '주요 이동평균선 아래'
        : '$aboveCount/${lines.length}개 이동평균선 위';
    final color = aboveCount == lines.length
        ? const Color(0xFF10B981)
        : aboveCount == 0
        ? const Color(0xFFF04452)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '이평선 위치',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.58),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                headline,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final closeX = width * pos(close);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 24,
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFF04452).withValues(alpha: 0.62),
                              const Color(0xFFF59E0B).withValues(alpha: 0.62),
                              const Color(0xFF10B981).withValues(alpha: 0.62),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ...lines.map((line) {
                      final x = width * pos(line.value!);
                      final isBelowPrice = close >= line.value!;
                      final lineColor = isBelowPrice
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF04452);
                      return Positioned(
                        left: (x - 18).clamp(0.0, width - 36),
                        top: isBelowPrice ? 30 : 0,
                        child: _MaMarker(
                          label: line.label,
                          color: lineColor,
                          filled: false,
                        ),
                      );
                    }),
                    Positioned(
                      left: (closeX - 26).clamp(0.0, width - 52),
                      top: 15,
                      child: _MaMarker(
                        label: '현재가',
                        color: color,
                        filled: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          Column(
            children: lines
                .map(
                  (line) => _MaGapRow(
                    label: line.label,
                    close: close,
                    value: line.value!,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MaLineData {
  final String label;
  final double? value;

  const _MaLineData({required this.label, required this.value});
}

class _MaMarker extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _MaMarker({
    required this.label,
    required this.color,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: filled ? 0 : 0.38)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MaGapRow extends StatelessWidget {
  final String label;
  final double close;
  final double value;

  const _MaGapRow({
    required this.label,
    required this.close,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final gap = ((close / value) - 1) * 100;
    final positive = gap >= 0;
    final color = positive ? const Color(0xFF10B981) : const Color(0xFFF04452);
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '$label선',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.58),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              positive ? '현재가가 위에 있습니다' : '현재가가 아래에 있습니다',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.70),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${positive ? '+' : ''}${gap.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvestorFlowTableRow extends StatelessWidget {
  final String date;
  final String foreign;
  final String institution;
  final String rate;
  final bool header;
  final bool foreignPositive;
  final bool institutionPositive;
  final bool ratePositive;

  const _InvestorFlowTableRow({
    required this.date,
    required this.foreign,
    required this.institution,
    required this.rate,
    this.header = false,
    this.foreignPositive = false,
    this.institutionPositive = false,
    this.ratePositive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.onSurface.withValues(alpha: header ? 0.48 : 0.74);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: header
            ? cs.onSurface.withValues(alpha: 0.035)
            : Colors.transparent,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.055)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 18,
            child: Text(
              date,
              style: TextStyle(
                color: baseColor,
                fontSize: 11.5,
                fontWeight: header ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 27,
            child: _FlowCell(
              text: foreign,
              positive: foreignPositive,
              header: header,
              align: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 27,
            child: _FlowCell(
              text: institution,
              positive: institutionPositive,
              header: header,
              align: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 22,
            child: _FlowCell(
              text: rate,
              positive: ratePositive,
              header: header,
              align: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowCell extends StatelessWidget {
  final String text;
  final bool positive;
  final bool header;
  final TextAlign align;

  const _FlowCell({
    required this.text,
    required this.positive,
    required this.header,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = header
        ? cs.onSurface.withValues(alpha: 0.48)
        : text.startsWith('-')
        ? const Color(0xFFF04452)
        : positive
        ? const Color(0xFF10B981)
        : cs.onSurface.withValues(alpha: 0.66);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: header ? FontWeight.w900 : FontWeight.w800,
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final _MetricRowData row;

  const _MetricRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _verdictColor(row.verdict);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.11)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.58),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              row.verdict,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreItem {
  final String label;
  final double value;
  final IconData icon;

  const _ScoreItem({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _SignalItem {
  final String title;
  final String value;
  final String body;
  final IconData icon;
  final bool danger;

  const _SignalItem({
    required this.title,
    required this.value,
    required this.body,
    required this.icon,
    this.danger = false,
  });
}

class _MetricRowData {
  final String label;
  final String value;
  final String verdict;

  const _MetricRowData({
    required this.label,
    required this.value,
    required this.verdict,
  });
}

class _AiTechnicalMetrics {
  final double? latestClose;
  final double? rsi14;
  final double? return5;
  final double? return20;
  final double? return60;
  final double? return120;
  final double? ma5;
  final double? ma20;
  final double? ma60;
  final double? ma120;
  final String? bollingerPosition;
  final String? bollingerVerdict;

  const _AiTechnicalMetrics({
    required this.latestClose,
    required this.rsi14,
    required this.return5,
    required this.return20,
    required this.return60,
    required this.return120,
    required this.ma5,
    required this.ma20,
    required this.ma60,
    required this.ma120,
    required this.bollingerPosition,
    required this.bollingerVerdict,
  });

  factory _AiTechnicalMetrics.fromCandles(List<Map<String, dynamic>> candles) {
    final closes = candles
        .map((c) => (c['close'] as num?)?.toDouble())
        .whereType<double>()
        .where((v) => v > 0)
        .toList();
    if (closes.length < 2) {
      return const _AiTechnicalMetrics(
        latestClose: null,
        rsi14: null,
        return5: null,
        return20: null,
        return60: null,
        return120: null,
        ma5: null,
        ma20: null,
        ma60: null,
        ma120: null,
        bollingerPosition: null,
        bollingerVerdict: null,
      );
    }

    final bollinger = _bollinger(closes);
    return _AiTechnicalMetrics(
      latestClose: closes.last,
      rsi14: _rsi(closes, 14),
      return5: _periodReturn(closes, 5),
      return20: _periodReturn(closes, 20),
      return60: _periodReturn(closes, 60),
      return120: _periodReturn(closes, 120),
      ma5: _movingAverage(closes, 5),
      ma20: _movingAverage(closes, 20),
      ma60: _movingAverage(closes, 60),
      ma120: _movingAverage(closes, 120),
      bollingerPosition: bollinger.$1,
      bollingerVerdict: bollinger.$2,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool fromCache;
  final String? generatedText;

  const _StatusCard({required this.fromCache, required this.generatedText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Color(0xFF10B981), size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              fromCache ? '개인 기록에서 불러온 분석입니다.' : '새 분석을 저장했습니다.',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (generatedText != null)
            Text(
              generatedText!,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
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
          const _CardTitle(
            icon: Icons.auto_awesome,
            title: '결론',
            color: Color(0xFF10B981),
          ),
          const SizedBox(height: 10),
          _ReadableText(text: text, dense: false),
        ],
      ),
    );
  }
}

class _ReadableText extends StatelessWidget {
  final String text;
  final bool dense;

  const _ReadableText({required this.text, this.dense = true});

  @override
  Widget build(BuildContext context) {
    final lines = _readableLines(text);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => Padding(
              padding: EdgeInsets.only(bottom: dense ? 8 : 9),
              child: _ReadableLine(line: line, dense: dense),
            ),
          )
          .toList(),
    );
  }
}

class _ReadableLine extends StatelessWidget {
  final String line;
  final bool dense;

  const _ReadableLine({required this.line, required this.dense});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = _parseDisplayLine(line);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.055)),
      ),
      child: parsed.label == null
          ? Text(
              parsed.body,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.76),
                fontSize: dense ? 13 : 14,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parsed.label!,
                  style: TextStyle(
                    color: const Color(0xFF14B8A6),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  parsed.body,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.76),
                    fontSize: dense ? 13 : 14,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
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
  final bool inverse;

  const _MarketPill({required this.market, this.inverse = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: inverse
            ? Colors.white.withValues(alpha: 0.16)
            : cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        market,
        style: TextStyle(
          color: inverse
              ? Colors.white.withValues(alpha: 0.84)
              : cs.onSurface.withValues(alpha: 0.54),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(ColorScheme cs) {
  return BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.025),
        blurRadius: 10,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

Color _scoreColor(double? score) {
  if (score == null) return const Color(0xFF64748B);
  if (score >= 75) return const Color(0xFF10B981);
  if (score >= 55) return const Color(0xFFF59E0B);
  return const Color(0xFFF04452);
}

double _scoreFromText(String text, double fallback) {
  final lower = text.toLowerCase();
  var score = fallback;
  const positiveWords = ['상승', '강세', '개선', '긍정', '확대', '돌파', '호조', '우호', '모멘텀'];
  const negativeWords = ['하락', '약세', '부정', '부담', '위험', '리스크', '둔화', '이탈', '악화'];
  for (final word in positiveWords) {
    if (lower.contains(word)) score += 5;
  }
  for (final word in negativeWords) {
    if (lower.contains(word)) score -= 6;
  }
  return score.clamp(0, 100).toDouble();
}

double _fundamentalScore(FundamentalsResult? fundamentals, double fallback) {
  if (fundamentals == null) return fallback;
  var score = fallback;
  final per = fundamentals.per;
  final pbr = fundamentals.pbr;
  if (per != null) {
    if (per > 0 && per <= 12) score += 8;
    if (per >= 25) score -= 8;
  }
  if (pbr != null) {
    if (pbr > 0 && pbr <= 1.2) score += 6;
    if (pbr >= 3) score -= 7;
  }
  return score.clamp(0, 100).toDouble();
}

String _signalLabel(String text) {
  final score = _scoreFromText(text, 55);
  if (score >= 68) return '우호적';
  if (score <= 42) return '주의 필요';
  return '중립';
}

String _peerPerCaption(StockAiAnalysisResult analysis) {
  final text = StockAiAnalysisResultScreen.cleanText(analysis.peerPerAverage);
  if (text.isEmpty) return '업종 평균 확인 필요';
  return _sanitizeDisplayLine(text);
}

String _themeDisplayText(String value) {
  var text = StockAiAnalysisResultScreen.cleanText(value);
  text = text.replaceAll(RegExp(r'(근거|이유|확인되는 강도|불확실성)\s*[:：].*$'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return value;
  return text;
}

String _newsDisplayText(StockAiAnalysisResult analysis) {
  final titles = analysis.sourceNews
      .map((item) => item.title.trim())
      .where((title) => title.isNotEmpty)
      .take(3)
      .toList();
  if (titles.isNotEmpty) return titles.join('\n');
  return analysis.news;
}

String _cleanScoreLabel(String value, int? scoreValue) {
  var text = StockAiAnalysisResultScreen.cleanText(value);
  text = _sanitizeDisplayLine(text);
  text = text.replaceAll(RegExp(r'\b중립\s*[-~·/]\s*우호\b'), '중립');
  text = text.replaceAll(RegExp(r'\b우호\s*[-~·/]\s*중립\b'), '중립');
  text = text.replaceAll(RegExp(r'우호\s*\([^)]*중립[^)]*\)'), '우호');
  text = text.replaceAll(RegExp(r'중립\s*\([^)]*우호[^)]*\)'), '중립');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final verdict = scoreValue == null
      ? ''
      : scoreValue >= 75
      ? '우호'
      : scoreValue >= 55
      ? '중립'
      : '주의';
  if (verdict.isEmpty || text.isEmpty) return text;
  final withoutLeading = text.replaceFirst(
    RegExp(r'^(우호적?|중립|주의|부정적?|긍정적?)\s*[:：\-·]?\s*'),
    '',
  );
  return '$verdict: $withoutLeading';
}

Color _signalColor(String label) {
  if (label.contains('낮') || label.contains('우호')) {
    return const Color(0xFF10B981);
  }
  if (label.contains('주의') || label.contains('개')) {
    return const Color(0xFFF04452);
  }
  return const Color(0xFFF59E0B);
}

String _valuationVerdict(double? value, {required bool lowGood}) {
  if (value == null || value <= 0) return '데이터 없음';
  if (lowGood && value <= 1.5) return '낮은 편';
  if (lowGood && value <= 12) return '보통';
  if (value >= 25) return '높은 편';
  return '확인 필요';
}

Color _verdictColor(String verdict) {
  if (verdict.contains('강세') ||
      verdict.contains('우호') ||
      verdict.contains('낮은') ||
      verdict.contains('상회') ||
      verdict.contains('공시 있음')) {
    return const Color(0xFF10B981);
  }
  if (verdict.contains('약세') ||
      verdict.contains('주의') ||
      verdict.contains('높은') ||
      verdict.contains('과열') ||
      verdict.contains('하회')) {
    return const Color(0xFFF04452);
  }
  return const Color(0xFFF59E0B);
}

double? _periodReturn(List<double> closes, int period) {
  if (closes.length <= period) return null;
  final base = closes[closes.length - 1 - period];
  if (base <= 0) return null;
  return ((closes.last / base) - 1) * 100;
}

double? _movingAverage(List<double> closes, int period) {
  if (closes.length < period) return null;
  final recent = closes.sublist(closes.length - period);
  return recent.reduce((a, b) => a + b) / recent.length;
}

double? _rsi(List<double> closes, int period) {
  if (closes.length <= period) return null;
  var gains = 0.0;
  var losses = 0.0;
  for (var i = closes.length - period; i < closes.length; i++) {
    final diff = closes[i] - closes[i - 1];
    if (diff >= 0) {
      gains += diff;
    } else {
      losses += diff.abs();
    }
  }
  final avgGain = gains / period;
  final avgLoss = losses / period;
  if (avgLoss == 0) return 100;
  final rs = avgGain / avgLoss;
  return 100 - (100 / (1 + rs));
}

(String?, String?) _bollinger(List<double> closes) {
  if (closes.length < 20) return (null, null);
  final recent = closes.sublist(closes.length - 20);
  final mean = recent.reduce((a, b) => a + b) / recent.length;
  final variance =
      recent.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
      recent.length;
  final sd = sqrt(variance);
  if (sd == 0) return ('중단', '변동성 낮음');
  final upper = mean + (2 * sd);
  final lower = mean - (2 * sd);
  final close = closes.last;
  if (close >= upper) return ('상단 접근', '과열 주의');
  if (close <= lower) return ('하단 접근', '반등 확인');
  if (close >= mean) return ('중상단', '우호적');
  return ('중하단', '중립');
}

String _formatPercent(double? value) {
  if (value == null) return '-';
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}%';
}

String _formatHeroChange(PriceResult? price) {
  if (price == null) return '-';
  final sign = price.change > 0
      ? '+'
      : price.change < 0
      ? '-'
      : '';
  final amount = price.isKrw
      ? price.change.abs().toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        )
      : price.change.abs().toStringAsFixed(2);
  final rate = price.changeRate.abs().toStringAsFixed(2);
  return '$sign$amount ($rate%)';
}

String _formatDartDate(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 8) return value;
  return '${digits.substring(0, 4)}.${digits.substring(4, 6)}.${digits.substring(6, 8)}';
}

String _formatSourceDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('yyyy.MM.dd').format(parsed.toLocal());
}

String _shortDate(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 8) {
    return '${digits.substring(4, 6)}.${digits.substring(6, 8)}';
  }
  return value;
}

String _returnVerdict(double? value) {
  if (value == null) return '데이터 없음';
  if (value >= 15) return '강세';
  if (value >= 3) return '우호적';
  if (value <= -10) return '약세';
  return '중립';
}

String _formatShareFlow(double? value) {
  if (value == null) return '-';
  final sign = value > 0 ? '+' : '';
  final abs = value.abs();
  final formatted = abs >= 10000
      ? '${(value / 10000).toStringAsFixed(1)}만주'
      : '${value.toStringAsFixed(0)}주';
  return '$sign$formatted';
}

String _shareFlowVerdict(double? value) {
  if (value == null) return '데이터 없음';
  if (value > 0) return '순매수';
  if (value < 0) return '순매도';
  return '중립';
}

String _rsiVerdict(double? value) {
  if (value == null) return '데이터 없음';
  if (value >= 70) return '과매수';
  if (value <= 30) return '과매도';
  if (value >= 60) return '과매수 접근';
  if (value <= 40) return '과매도 접근';
  return '중립권';
}

String _analysisAllText(StockAiAnalysisResult analysis) {
  return [
    analysis.summary,
    analysis.theme,
    analysis.sector,
    analysis.todayReason,
    analysis.fundamentals,
    analysis.technical,
    analysis.news,
    analysis.momentum,
    ...analysis.risks,
    ...analysis.sections.map((s) => '${s.title} ${s.body}'),
  ].join(' ');
}

String _formatMarketCap(int value) {
  if (value >= 1000000000000) {
    return '${(value / 1000000000000).toStringAsFixed(1)}조';
  }
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(0)}억';
  }
  return NumberFormat('#,###').format(value);
}

int? _marketCapFromAnalysis(StockAiAnalysisResult analysis) {
  final text = _analysisAllText(analysis);
  final patterns = [
    RegExp(r'시가총액(?:\(KIS\))?\s*[:：]?\s*([\d,]+(?:\.\d+)?)\s*억원'),
    RegExp(r'시총\s*[:：]?\s*([\d,]+(?:\.\d+)?)\s*억원'),
    RegExp(r'([\d,]+(?:\.\d+)?)\s*억원\s*(?:규모의\s*)?시가총액'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    final value = double.tryParse(match?.group(1)?.replaceAll(',', '') ?? '');
    if (value != null) return (value * 100000000).round();
  }

  final trillionMatch = RegExp(
    r'시가총액(?:\(KIS\))?\s*[:：]?\s*([\d,]+(?:\.\d+)?)\s*조',
  ).firstMatch(text);
  final trillion = double.tryParse(
    trillionMatch?.group(1)?.replaceAll(',', '') ?? '',
  );
  if (trillion != null) return (trillion * 1000000000000).round();
  return null;
}

String _formatFinancialAmountToEok(String value) {
  final text = value.trim();
  if (text.isEmpty || text == 'N/A') return text.isEmpty ? '-' : text;
  if (text.contains('억') || text.contains('조')) return text;
  final normalized = text.replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');
  final number = double.tryParse(normalized);
  if (number == null) return text;
  final eok = number / 100000000;
  if (eok.abs() >= 10000) {
    final jo = eok / 10000;
    return '${jo.toStringAsFixed(jo.abs() >= 10 ? 1 : 2)}조원';
  }
  if (eok.abs() >= 10) return '${eok.toStringAsFixed(0)}억원';
  if (eok.abs() >= 1) return '${eok.toStringAsFixed(1)}억원';
  return '${eok.toStringAsFixed(2)}억원';
}

String _dartDisclosureUrl(String receiptNo) {
  final digits = receiptNo.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  return 'https://dart.fss.or.kr/dsaf001/main.do?rcpNo=$digits';
}

List<String> _readableLines(String value) {
  final normalized = value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('", "', '\n')
      .replaceAll(RegExp(r'\s*[;；]\s*'), '\n')
      .trim();
  if (normalized.isEmpty) return const [];

  final lines = <String>[];
  for (final block in normalized.split(RegExp(r'\n+'))) {
    final trimmed = _sanitizeDisplayLine(block);
    if (trimmed.isEmpty) continue;
    if (trimmed.length <= 130) {
      lines.add(trimmed);
      continue;
    }
    final pieces = trimmed.split('. ');
    for (var i = 0; i < pieces.length; i++) {
      var piece = pieces[i].trim();
      if (piece.isEmpty) continue;
      if (i < pieces.length - 1 && !piece.endsWith('.')) piece = '$piece.';
      lines.add(piece);
    }
  }
  return lines
      .map(_sanitizeDisplayLine)
      .where((line) => line.trim().isNotEmpty)
      .take(10)
      .toList();
}

String _sanitizeDisplayLine(String value) {
  var text = value.trim();
  text = text.replaceAll(RegExp(r'^[•\-\*\s]+'), '');
  text = text.replaceAll(RegExp(r'^(KIS|OpenDART)\s*데이터\s*[:：]\s*'), '');
  text = text.replaceAll(RegExp(r'\s*\((?:KIS|OpenDART)\s*기준\)'), '');
  text = text.replaceAll(RegExp(r'\s*\((?:KIS|OpenDART)\)'), '');
  text = text.replaceAll(RegExp(r'\s*(?:KIS|OpenDART)\s*기준\s*'), ' ');
  text = text.replaceAll(RegExp(r'\s*OpenDART\s*'), ' ');
  text = text.replaceAll(RegExp(r'\s*KIS\s*'), ' ');
  text = text.replaceAll('단위 확인 필요', '기준 단위 확인이 필요합니다');
  text = text.replaceAll('표기됩니다', '확인됩니다');
  text = text.replaceAll('EPS 역산:', 'EPS 확인');
  text = text.replaceAll(
    RegExp(r'5\s*/\s*20\s*/\s*60\s*/\s*120일\s*대비\s*모두\s*상회(?:하고)?'),
    '5·20·60·120일 이동평균선 위에 있고',
  );
  text = text.replaceAll(
    RegExp(r'5\s*/\s*20\s*/\s*60\s*/\s*120일선?\s*대비\s*모두\s*상회(?:하고)?'),
    '5·20·60·120일 이동평균선 위에 있고',
  );
  text = text.replaceAll(RegExp(r'\b상회하고\b'), '위에 있고');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.replaceAll(RegExp(r'\s+([,.])'), r'$1');
  return text.trim();
}

({String? label, String body}) _parseDisplayLine(String value) {
  final text = _sanitizeDisplayLine(value);
  final match = RegExp(
    r'^([가-힣A-Za-z0-9 /·%()]{2,18})\s*[:：]\s*(.+)$',
  ).firstMatch(text);
  if (match == null) return (label: null, body: text);
  final label = match.group(1)?.trim();
  final body = match.group(2)?.trim() ?? text;
  if (label == null || label.length > 18 || body.isEmpty) {
    return (label: null, body: text);
  }
  return (label: label, body: body);
}
