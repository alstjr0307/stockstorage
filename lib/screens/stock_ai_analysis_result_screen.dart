import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

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
    text = _stripSourceReferences(text);
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
    text = cleanText(text);
    // 메타 코멘트 / placeholder 제거
    text = _stripMetaPhrases(text);
    return text;
  }

  static String _stripMetaPhrases(String value) {
    var text = value;
    // 첫 문장 자기 메타 코멘트 제거
    text = text.replaceFirst(
      RegExp(r'^(중립|우호|주의|긍정|부정)\s*성향의?\s*리포트입니다[\.\s]*'),
      '',
    );
    text = text.replaceFirst(RegExp(r'^(본\s*)?(리포트|분석|보고서)는[^\.]*\.\s*'), '');
    text = text.replaceFirst(
      RegExp(r'^(이|본)\s*(리포트|분석|보고서)에서는?[^\.]*\.\s*'),
      '',
    );
    // 비공개/placeholder 표현 제거
    text = text.replaceAll(RegExp(r'\s*\(\s*(정량적?\s*내용\s*)?비공개\s*\)\s*'), ' ');
    text = text.replaceAll(RegExp(r'\s*\(\s*자세한\s*수치는?\s*비공개\s*\)\s*'), ' ');
    text = text.replaceAll(RegExp(r'\s*\(\s*비공개\s*\)\s*'), ' ');
    text = text.replaceAll(RegExp(r'\s*미확인\s*변수[^.\n]*\.?'), '');
    text = text.replaceAllMapped(
      RegExp(
        r'(^|[.!?\n]\s*)(핵심\s*원인(?:은)?|주요\s*원인|근거\s*뉴스\s*/?\s*공시|거래\s*/?\s*가격\s*반응|설명\s*한계)\s*[:：]?\s*',
      ),
      (match) => match.group(1) ?? '',
    );
    // 데이터 출처 메타 (KIS/OpenDART) 제거
    text = text.replaceAll(
      RegExp(r'\s*\(\s*(KIS|OpenDART)\s*(기준|데이터)?\s*\)\s*'),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\s*(KIS|OpenDART)\s*기준\s*'), ' ');
    text = _stripSourceReferences(text);
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  static String _stripSourceReferences(String value) {
    var text = value;
    text = text.replaceAll(
      RegExp(
        r'\b20\d{2}[-./]\d{2}[-./]\d{2}\s*(?:\[[^\]]+\])?\s*[^.\n,，]*?(?:공시|보고서|신고서|주요경영사항|투자판단관련주요경영사항)[^.\n,，]*(?=[.\n,，]|$)',
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(r'\s*(?:근거|출처)\s*[:：]\s*[^.\n]+(?=[.\n]|$)'),
      '',
    );
    text = text.replaceAll(
      RegExp(r'\s*(?:뉴스|공시)\s*(?:헤드라인|제목)\s*[:：]\s*[^.\n]+(?=[.\n]|$)'),
      '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\s+([.,，.])'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
    return text.trim();
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
  List<Map<String, dynamic>> _analysisCandlesForChart = const [];
  bool _loading = true;
  bool _fromCache = false;
  int _elapsedSeconds = 0;
  String? _error;

  static const _loadingMessages = [
    '개인 기록에서 기존 분석을 확인하고 있어요',
    '최근 뉴스와 당일 흐름을 정리하고 있어요',
    'PER · PBR · BPS 같은 밸류 지표를 맞춰보고 있어요',
    '캔들 · 이동평균 · 지지/저항을 읽고 있어요',
    '점수와 리스크를 마무리하고 있어요',
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
            _analysisCandlesForChart = candles;
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
        _analysisCandlesForChart = candles;
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
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.pick.name,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.pick.ticker} · ${widget.pick.market}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.42),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading && _analysis != null)
            IconButton(
              tooltip: '새로 분석',
              icon: Icon(
                Icons.refresh,
                color: cs.onSurface.withValues(alpha: 0.62),
                size: 20,
              ),
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
      candles: _analysisCandlesForChart,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF10B981);
    final progress = ((elapsedSeconds % 24) + 1) / 24;

    final steps = [
      ('기존 분석 기록 확인', 1, 4),
      ('뉴스 · 당일 등락 원인 요약', 4, 7),
      ('재무 · 밸류에이션 점검', 7, 10),
      ('차트 · 기술 지표 해석', 10, 13),
      ('점수 · 리스크 마무리', 13, 999),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 34),
      physics: const ClampingScrollPhysics(),
      children: [
        Text(
          'AI 딥분석 작성 중',
          style: TextStyle(
            color: accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          pick.name,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              pick.ticker,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '  ·  ${pick.market}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        ClipRRect(
          borderRadius: BorderRadius.circular(9999),
          child: LinearProgressIndicator(
            minHeight: 3,
            value: progress,
            color: accent,
            backgroundColor: cs.onSurface.withValues(alpha: 0.06),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$elapsedSeconds초 경과',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        Text(
          message,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.88),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.45,
          ),
        ),

        const SizedBox(height: 28),

        Text(
          '진행 상태',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++) ...[
          _ChecklistRow(
            label: steps[i].$1,
            done: elapsedSeconds >= steps[i].$3,
            active: elapsedSeconds >= steps[i].$2 &&
                elapsedSeconds < steps[i].$3,
            accent: accent,
          ),
          if (i < steps.length - 1) const SizedBox(height: 14),
        ],

        const SizedBox(height: 32),

        Text(
          '처음 한 번만 생성하면\n이후에는 개인 기록에서 바로 불러옵니다.',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 12,
            height: 1.6,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  final String label;
  final bool done;
  final bool active;
  final Color accent;

  const _ChecklistRow({
    required this.label,
    required this.done,
    required this.active,
    required this.accent,
  });

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ChecklistRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.done
        ? cs.onSurface.withValues(alpha: 0.92)
        : widget.active
            ? cs.onSurface.withValues(alpha: 0.78)
            : cs.onSurface.withValues(alpha: 0.32);
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: widget.done
                ? Icon(Icons.check_rounded, size: 16, color: widget.accent)
                : widget.active
                    ? AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, _) {
                          final t = 0.35 + 0.65 * _pulse.value;
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: t),
                              shape: BoxShape.circle,
                            ),
                          );
                        },
                      )
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontSize: 14.5,
              fontWeight: widget.done || widget.active
                  ? FontWeight.w700
                  : FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
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
  final List<Map<String, dynamic>> candles;

  const _AnalysisContent({
    required this.pick,
    required this.analysis,
    required this.price,
    required this.fundamentals,
    required this.fromCache,
    required this.technicalMetrics,
    required this.candles,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final generatedText = analysis.generatedAt == null
        ? null
        : DateFormat('yyyy.MM.dd HH:mm').format(analysis.generatedAt!);
    final summaryText = StockAiAnalysisResultScreen.cleanSummaryText(
      analysis.summary,
    );

    final hasCatalysts = analysis.catalysts.isNotEmpty;
    final hasScenarios =
        analysis.scenarios != null &&
        (analysis.scenarios!.bull != null ||
            analysis.scenarios!.base != null ||
            analysis.scenarios!.bear != null);
    final hasTiming =
        analysis.timing != null &&
        (analysis.timing!.shortTerm.isNotEmpty ||
            analysis.timing!.midTerm.isNotEmpty ||
            analysis.timing!.action.isNotEmpty);
    final risksDetailed = analysis.risksDetailed
        .where(
          (risk) =>
              risk.description.trim().isNotEmpty ||
              risk.mitigant.trim().isNotEmpty,
        )
        .toList();
    final hasRisksDetailed = risksDetailed.isNotEmpty;
    final relatedPeers = _relatedPeers(analysis);

    final content = <Widget>[];
    void addSection(Widget child, {double gap = 18}) {
      if (content.isNotEmpty) content.add(SizedBox(height: gap));
      content.add(child);
    }

    addSection(
      _ReportHeroCard(
        pick: pick,
        price: price,
        analysis: analysis,
        summary: summaryText,
        generatedText: generatedText,
        candles: candles,
      ),
      gap: 0,
    );
    addSection(
      _ScoreBoardCard(analysis: analysis, fundamentals: fundamentals),
      gap: 22,
    );
    addSection(
      _SnapshotGrid(
        analysis: analysis,
        price: price,
        fundamentals: fundamentals,
        technicalMetrics: technicalMetrics,
      ),
    );
    if (hasCatalysts) {
      addSection(_CatalystsCard(catalysts: analysis.catalysts));
    } else if (_hasReadableSignalContent(analysis)) {
      addSection(_SignalGridCard(analysis: analysis));
    }
    if (relatedPeers.isNotEmpty) {
      addSection(_ThemePeersCard(peers: relatedPeers));
    }
    if (hasScenarios) {
      addSection(_ScenariosCard(scenarios: analysis.scenarios!));
    }
    if (hasTiming) {
      addSection(_TimingCard(timing: analysis.timing!));
    }
    addSection(
      _DataRoomCard(
        fundamentals: fundamentals,
        analysis: analysis,
        technicalMetrics: technicalMetrics,
      ),
    );
    final renderableSections = analysis.sections
        .where((s) => s.title.isNotEmpty && s.body.trim().isNotEmpty)
        .toList();
    if (renderableSections.isNotEmpty) {
      addSection(_SectionsCard(sections: renderableSections));
    }
    if (hasRisksDetailed) {
      addSection(_RisksDetailedCard(risks: risksDetailed));
    }
    addSection(_SourceEvidenceCard(analysis: analysis));
    addSection(
      _StatusCard(fromCache: fromCache, generatedText: generatedText),
      gap: 16,
    );
    addSection(
      Text(
        'AI 분석은 학습과 참고용입니다.\n투자 판단과 결과에 대한 책임은 본인에게 있습니다.',
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.4),
          fontSize: 11.5,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
      gap: 10,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        for (var i = 0; i < content.length; i++)
          _StaggeredFadeIn(index: i, child: content[i]),
      ],
    );
  }
}

class _StaggeredFadeIn extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredFadeIn({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: 34 * min(index, 10));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final start = delay.inMilliseconds / (420 + delay.inMilliseconds);
        final progress = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 15.5,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _SummaryParagraphs extends StatelessWidget {
  final String text;

  const _SummaryParagraphs({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paragraphs = _splitParagraphs(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i < paragraphs.length - 1 ? 10 : 0,
            ),
            child: Text(
              paragraphs[i],
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
      ],
    );
  }

  static List<String> _splitParagraphs(String text) {
    // 1순위: 두 줄바꿈으로 명시된 문단 분리
    final byBlankLines = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (byBlankLines.length > 1) return byBlankLines;
    // 2순위: 마침표·물음표·느낌표 뒤 공백 기준 split (단, 숫자 소수점은 제외)
    final regex = RegExp(r'(?<=[.!?다요])\s+(?=[가-힣A-Za-z0-9])');
    final sentences = text
        .split(regex)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return sentences.isEmpty ? [text.trim()] : sentences;
  }
}

class _ReportHeroCard extends StatelessWidget {
  final StockPick pick;
  final PriceResult? price;
  final StockAiAnalysisResult analysis;
  final String summary;
  final String? generatedText;
  final List<Map<String, dynamic>> candles;

  const _ReportHeroCard({
    required this.pick,
    required this.price,
    required this.analysis,
    required this.summary,
    required this.generatedText,
    required this.candles,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = analysis.score;
    final scoreColor = _scoreColor(score);
    final scoreValue = score?.round();
    final scoreText = scoreValue == null ? '--' : scoreValue.toString();
    final scoreCaption = scoreValue == null
        ? '대기'
        : scoreValue >= 75
        ? '우호적'
        : scoreValue >= 55
        ? '중립'
        : '주의';
    final priceChange = price?.change ?? 0;
    final changeColor = priceChange >= 0
        ? const Color(0xFFF04452)
        : const Color(0xFF4D9BFF);
    final priceText = price?.formattedPrice ?? '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'AI 종목 분석',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              if (generatedText != null) ...[
                const SizedBox(width: 8),
                Text(
                  '·',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.22),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '$generatedText 생성',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    priceText,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          priceChange >= 0
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                          color: changeColor,
                          size: 18,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _formatHeroChange(price),
                          style: TextStyle(
                            color: changeColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(
                      value: score == null ? 0 : score.clamp(0, 100) / 100,
                      strokeWidth: 8,
                      color: scoreColor,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        scoreText,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        scoreCaption,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (analysis.companyOverview.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          _CompanyOverviewCard(text: analysis.companyOverview.trim()),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          if (candles.length >= 2) ...[
            _PriceChartCard(candles: candles),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 14, 13),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: const Border(
                left: BorderSide(color: Color(0xFF10B981), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '간단 요약',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _SummaryParagraphs(text: summary),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CompanyOverviewCard extends StatelessWidget {
  final String text;

  const _CompanyOverviewCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF9B7BFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 14, 13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_rounded, size: 13, color: accent),
              const SizedBox(width: 5),
              const Text(
                '기업 소개',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.88),
              fontSize: 13.5,
              height: 1.6,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChartCard extends StatefulWidget {
  final List<Map<String, dynamic>> candles;

  const _PriceChartCard({required this.candles});

  @override
  State<_PriceChartCard> createState() => _PriceChartCardState();
}

class _PriceChartCardState extends State<_PriceChartCard> {
  bool _candleMode = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = widget.candles
        .map(_ChartCandle.fromMap)
        .where((c) => c.close > 0 && c.high > 0 && c.low > 0)
        .toList();
    if (points.length < 2) return const SizedBox.shrink();
    final visible = points.length > 80
        ? points.sublist(points.length - 80)
        : points;
    final first = visible.first.close;
    final last = visible.last.close;
    final change = first <= 0 ? 0.0 : ((last / first) - 1) * 100;
    final color = change >= 0
        ? const Color(0xFFF04452)
        : const Color(0xFF4D9BFF);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '최근 가격 흐름',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              _ChartToggle(
                selected: !_candleMode,
                text: '선',
                onTap: () => setState(() => _candleMode = false),
              ),
              const SizedBox(width: 5),
              _ChartToggle(
                selected: _candleMode,
                text: '캔들',
                onTap: () => setState(() => _candleMode = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 148,
            width: double.infinity,
            child: CustomPaint(
              painter: _PriceChartPainter(
                candles: visible,
                candleMode: _candleMode,
                lineColor: color,
                gridColor: cs.onSurface.withValues(alpha: 0.06),
                textColor: cs.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartToggle extends StatelessWidget {
  final bool selected;
  final String text;
  final VoidCallback onTap;

  const _ChartToggle({
    required this.selected,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.16)
              : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected
                ? const Color(0xFF10B981)
                : cs.onSurface.withValues(alpha: 0.46),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ChartCandle {
  final double open;
  final double high;
  final double low;
  final double close;

  const _ChartCandle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory _ChartCandle.fromMap(Map<String, dynamic> map) {
    double value(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return _ChartCandle(
      open: value('open'),
      high: value('high'),
      low: value('low'),
      close: value('close'),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  final List<_ChartCandle> candles;
  final bool candleMode;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;

  const _PriceChartPainter({
    required this.candles,
    required this.candleMode,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(
      4,
      8,
      max(1, size.width - 46),
      max(1, size.height - 24),
    );
    final highs = candles.map((c) => c.high);
    final lows = candles.map((c) => c.low);
    var maxPrice = highs.reduce(max);
    var minPrice = lows.reduce(min);
    if (maxPrice == minPrice) {
      maxPrice += 1;
      minPrice -= 1;
    }
    final baseRange = maxPrice - minPrice;
    maxPrice += baseRange * 0.08;
    minPrice -= baseRange * 0.08;

    double xAt(int i) =>
        chart.left + chart.width * i / max(1, candles.length - 1);
    double yAt(double price) =>
        chart.bottom -
        ((price - minPrice) / (maxPrice - minPrice)) * chart.height;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    if (candleMode) {
      final candleWidth = max(
        2.0,
        min(7.0, chart.width / candles.length * 0.55),
      );
      for (var i = 0; i < candles.length; i++) {
        final c = candles[i];
        final x = xAt(i);
        final up = c.close >= c.open;
        final paint = Paint()
          ..color = up ? const Color(0xFFF04452) : const Color(0xFF4D9BFF)
          ..strokeWidth = 1.2;
        canvas.drawLine(Offset(x, yAt(c.high)), Offset(x, yAt(c.low)), paint);
        final top = yAt(max(c.open, c.close));
        final bottom = yAt(min(c.open, c.close));
        final rect = Rect.fromLTRB(
          x - candleWidth / 2,
          min(top, bottom),
          x + candleWidth / 2,
          max(top + 1.5, bottom),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          paint,
        );
      }
    } else {
      final path = Path();
      for (var i = 0; i < candles.length; i++) {
        final point = Offset(xAt(i), yAt(candles[i].close));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      final fillPath = Path.from(path)
        ..lineTo(chart.right, chart.bottom)
        ..lineTo(chart.left, chart.bottom)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()..color = lineColor.withValues(alpha: 0.08),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final labelStyle = TextStyle(
      color: textColor,
      fontSize: 10,
      fontWeight: FontWeight.w800,
    );
    for (final price in [maxPrice, minPrice]) {
      final painter = TextPainter(
        text: TextSpan(
          text: NumberFormat.compact().format(price),
          style: labelStyle,
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 40);
      painter.paint(canvas, Offset(chart.right + 6, yAt(price) - 6));
    }
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.candleMode != candleMode ||
        oldDelegate.lineColor != lineColor;
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
        caption: _peerPerShort(analysis),
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
        crossAxisCount: 4,
        mainAxisExtent: 96,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.52),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
              height: 1.2,
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
    final items = <_ScoreItem>[
      _ScoreItem(label: '뉴스', value: _scoreFromText(analysis.news, base)),
      _ScoreItem(label: '차트', value: _scoreFromText(analysis.technical, base)),
      _ScoreItem(label: '재무', value: _fundamentalScore(fundamentals, base)),
      _ScoreItem(label: '모멘텀', value: _scoreFromText(analysis.momentum, base)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('점수 구성'),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _ScoreTile(item: items[i], showBorder: i < items.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final _ScoreItem item;
  final bool showBorder;

  const _ScoreTile({required this.item, required this.showBorder});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _scoreColor(item.value);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              item.label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.68),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: item.value.clamp(0, 100) / 100,
                minHeight: 7,
                backgroundColor: cs.onSurface.withValues(alpha: 0.07),
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text(
              item.value.round().toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
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
    final signals = _visibleSignals(analysis);

    if (signals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('핵심 포인트'),
        for (var i = 0; i < signals.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < signals.length - 1 ? 8 : 0),
            child: _SignalRow(signal: signals[i]),
          ),
      ],
    );
  }
}

List<_SignalItem> _visibleSignals(StockAiAnalysisResult analysis) {
  return [
    _SignalItem(
      title: '최근 이슈',
      value: _signalLabel(analysis.todayReason),
      body: analysis.todayReason,
    ),
    _SignalItem(
      title: '테마',
      value: _signalLabel(analysis.theme),
      body: _themeDisplayText(analysis.theme),
    ),
    _SignalItem(
      title: '뉴스 방향',
      value: _signalLabel(analysis.news),
      body: _newsDisplayText(analysis),
    ),
    _SignalItem(
      title: '리스크',
      value: analysis.risks.isEmpty ? '낮음' : '${analysis.risks.length}개',
      body: analysis.risks.join('\n'),
      danger: analysis.risks.length >= 3,
    ),
  ].where((signal) {
    final body = StockAiAnalysisResultScreen.cleanText(signal.body);
    if (body.isEmpty || body == '-') return false;
    if (signal.title == '리스크' && analysis.risks.isEmpty) return false;
    return _readableLines(body).isNotEmpty;
  }).toList();
}

bool _hasReadableSignalContent(StockAiAnalysisResult analysis) {
  return _visibleSignals(analysis).isNotEmpty;
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
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 2, color: color),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            child: _SignalRowBody(signal: signal, color: color, body: body),
          ),
        ],
      ),
    );
  }
}

class _SignalRowBody extends StatelessWidget {
  final _SignalItem signal;
  final Color color;
  final String body;

  const _SignalRowBody({
    required this.signal,
    required this.color,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                signal.title,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(height: 11),
        if (body.isEmpty || body == '-')
          Text(
            '확인 가능한 근거가 부족합니다.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Builder(
            builder: (_) {
              final lines = _readableLines(body);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i < lines.length - 1 ? 7 : 0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 8, right: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              lines[i],
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.82),
                                fontSize: 13.5,
                                height: 1.55,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
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
                '같은 테마·섹터 종목',
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

class _SourceEvidenceCard extends StatefulWidget {
  final StockAiAnalysisResult analysis;

  const _SourceEvidenceCard({required this.analysis});

  @override
  State<_SourceEvidenceCard> createState() => _SourceEvidenceCardState();
}

class _SourceEvidenceCardState extends State<_SourceEvidenceCard> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final analysis = widget.analysis;
    final newsRows = analysis.sourceNews
        .take(6)
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
        .toList();
    final reportRows = analysis.sourceReports
        .take(5)
        .map(
          (item) => _SourceLine(
            title: item.title,
            meta: [
              if (item.publisher.isNotEmpty) item.publisher,
              _formatSourceDate(item.publishedAt),
              if (item.opinion.isNotEmpty) item.opinion,
              if (item.targetPrice != null)
                '목표가 ${_formatWon(item.targetPrice!)}',
            ].where((v) => v.isNotEmpty).join(' · '),
            url: item.url,
          ),
        )
        .toList();
    final disclosureRows = analysis.sourceDisclosures
        .take(6)
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
        .toList();
    final financialRows = analysis.sourceFinancials
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
        .toList();

    final tabs = <_SourceTabData>[
      _SourceTabData(
        label: '뉴스',
        rows: newsRows,
        color: const Color(0xFF10B981),
      ),
      _SourceTabData(
        label: '리포트',
        rows: reportRows,
        color: const Color(0xFF38BDF8),
      ),
      _SourceTabData(
        label: '공시',
        rows: disclosureRows,
        color: const Color(0xFF9B7BFF),
      ),
      _SourceTabData(
        label: '재무',
        rows: financialRows,
        color: const Color(0xFFF59E0B),
      ),
    ].where((tab) => tab.rows.isNotEmpty).toList();
    if (tabs.isEmpty) return const SizedBox.shrink();

    final clampedIndex = _tabIndex.clamp(0, tabs.length - 1);
    final active = tabs[clampedIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('근거 소스'),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.onSurface.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: _SourceTab(
                          data: tabs[i],
                          selected: i == clampedIndex,
                          onTap: () => setState(() => _tabIndex = i),
                        ),
                      ),
                  ],
                ),
              ),
              if (active.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '표시할 ${active.label}이 없습니다.',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.42),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Column(children: active.rows),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceTabData {
  final String label;
  final List<Widget> rows;
  final Color color;

  const _SourceTabData({
    required this.label,
    required this.rows,
    required this.color,
  });
}

class _SourceTab extends StatelessWidget {
  final _SourceTabData data;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTab({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelColor = selected
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.42);
    final countColor = selected
        ? data.color
        : cs.onSurface.withValues(alpha: 0.22);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  data.rows.length.toString(),
                  style: TextStyle(
                    color: countColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                left: 24,
                right: 24,
                bottom: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: data.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (canOpen) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new,
                  size: 15,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              meta,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
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

class _DataRoomCard extends StatefulWidget {
  final FundamentalsResult? fundamentals;
  final StockAiAnalysisResult analysis;
  final _AiTechnicalMetrics? technicalMetrics;

  const _DataRoomCard({
    required this.fundamentals,
    required this.analysis,
    required this.technicalMetrics,
  });

  @override
  State<_DataRoomCard> createState() => _DataRoomCardState();
}

class _DataRoomCardState extends State<_DataRoomCard> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final resolved = _ResolvedFundamentals.from(
      widget.fundamentals,
      widget.analysis,
    );
    final rows = [
      _MetricRowData(
        label: 'PER',
        value: resolved.per == null ? '-' : resolved.per!.toStringAsFixed(1),
        verdict: _peerPerCaption(widget.analysis),
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
        value: widget.technicalMetrics?.rsi14 == null
            ? '-'
            : widget.technicalMetrics!.rsi14!.toStringAsFixed(1),
        verdict: _rsiVerdict(widget.technicalMetrics?.rsi14),
      ),
      _MetricRowData(
        label: '5일 수익률',
        value: _formatPercent(widget.technicalMetrics?.return5),
        verdict: _returnVerdict(widget.technicalMetrics?.return5),
      ),
      _MetricRowData(
        label: '20일 수익률',
        value: _formatPercent(widget.technicalMetrics?.return20),
        verdict: _returnVerdict(widget.technicalMetrics?.return20),
      ),
      _MetricRowData(
        label: '60일 수익률',
        value: _formatPercent(widget.technicalMetrics?.return60),
        verdict: _returnVerdict(widget.technicalMetrics?.return60),
      ),
      _MetricRowData(
        label: '120일 수익률',
        value: _formatPercent(widget.technicalMetrics?.return120),
        verdict: _returnVerdict(widget.technicalMetrics?.return120),
      ),
      _MetricRowData(
        label: '볼린저 위치',
        value: widget.technicalMetrics?.bollingerPosition ?? '-',
        verdict: widget.technicalMetrics?.bollingerVerdict ?? '데이터 없음',
      ),
      _MetricRowData(
        label: '외국인 2주',
        value: _formatShareFlow(
          widget.analysis.sourceDailyInvestorFlow?.foreignNet14,
        ),
        verdict: _shareFlowVerdict(
          widget.analysis.sourceDailyInvestorFlow?.foreignNet14,
        ),
      ),
      _MetricRowData(
        label: '기관 2주',
        value: _formatShareFlow(
          widget.analysis.sourceDailyInvestorFlow?.institutionNet14,
        ),
        verdict: _shareFlowVerdict(
          widget.analysis.sourceDailyInvestorFlow?.institutionNet14,
        ),
      ),
      _MetricRowData(
        label: '외국인 보유율',
        value:
            widget.analysis.sourceDailyInvestorFlow?.latestForeignHoldRate ==
                null
            ? '-'
            : '${widget.analysis.sourceDailyInvestorFlow!.latestForeignHoldRate!.toStringAsFixed(2)}%',
        verdict:
            widget.analysis.sourceDailyInvestorFlow?.latestForeignHoldRate ==
                null
            ? '데이터 없음'
            : '최근 기준',
      ),
    ];
    final valuationRows = rows.take(5).toList();
    final technicalRows = rows.skip(5).take(6).toList();
    final flowRows = rows.skip(11).toList();
    final valuation = widget.analysis.valuation;
    final technicalDetail = widget.analysis.technicalDetail;
    final hasValuationFooter =
        valuation != null &&
        (valuation.peerComparison.isNotEmpty ||
            valuation.forwardPer.isNotEmpty ||
            valuation.sectorAveragePer.isNotEmpty ||
            valuation.reasoning.isNotEmpty);
    final epsTimeline = widget.analysis.sourceEpsTimeline;
    final hasEpsTimeline = epsTimeline.isNotEmpty;
    final valuationFooter = (hasValuationFooter || hasEpsTimeline)
        ? Column(
            children: [
              if (hasValuationFooter)
                _PeerComparisonFooter(valuation: valuation),
              if (hasEpsTimeline)
                _EpsTimelineFooter(timeline: epsTimeline),
            ],
          ) as Widget?
        : null;
    final tabs = [
      (
        label: '밸류에이션',
        rows: valuationRows,
        footer: valuationFooter,
      ),
      (
        label: '기술 지표',
        rows: technicalRows,
        footer:
            Column(
                  children: [
                    _MovingAveragePositionCard(
                      metrics: widget.technicalMetrics,
                    ),
                    if (technicalDetail != null)
                      _TechnicalDetailFooter(detail: technicalDetail),
                  ],
                )
                as Widget?,
      ),
      (
        label: '수급',
        rows: flowRows,
        footer: _InvestorFlowTable(
          flow: widget.analysis.sourceDailyInvestorFlow,
        ),
      ),
    ];
    final active = tabs[_tabIndex.clamp(0, tabs.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('데이터 보드'),
        _DataTabs(
          tabs: tabs.map((tab) => tab.label).toList(),
          selectedIndex: _tabIndex,
          onChanged: (index) => setState(() => _tabIndex = index),
        ),
        const SizedBox(height: 8),
        _MetricPanel(rows: active.rows, footer: active.footer),
      ],
    );
  }
}

class _DataTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _DataTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedIndex == i
                        ? cs.onSurface.withValues(alpha: 0.07)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selectedIndex == i
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.48),
                      fontSize: 13.5,
                      fontWeight: selectedIndex == i
                          ? FontWeight.w900
                          : FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpsTimelineFooter extends StatelessWidget {
  final List<StockAiEpsPoint> timeline;

  const _EpsTimelineFooter({required this.timeline});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actualPoints = timeline.where((p) => !p.estimate).toList();
    final estimatePoints = timeline.where((p) => p.estimate).toList();
    final hasMix = actualPoints.isNotEmpty && estimatePoints.isNotEmpty;
    String? growthLabel;
    if (hasMix) {
      final lastActual = actualPoints.last.eps;
      final lastEstimate = estimatePoints.last.eps;
      if (lastActual != null && lastEstimate != null && lastActual != 0) {
        final pct = ((lastEstimate - lastActual) / lastActual.abs()) * 100;
        final sign = pct >= 0 ? '+' : '';
        growthLabel =
            '실적 ${actualPoints.last.period} → 컨센서스 ${estimatePoints.last.period} $sign${pct.toStringAsFixed(1)}%';
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EPS·PER 컨센서스 추이',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (growthLabel != null)
                Text(
                  growthLabel,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                for (var i = 0; i < timeline.length; i++) ...[
                  _EpsPointChip(point: timeline[i]),
                  if (i < timeline.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpsPointChip extends StatelessWidget {
  final StockAiEpsPoint point;

  const _EpsPointChip({required this.point});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = point.estimate
        ? const Color(0xFF9B7BFF)
        : const Color(0xFF14B8A6);
    final eps = point.eps;
    final epsText = eps == null
        ? '-'
        : NumberFormat('#,###').format(eps.round());
    final per = point.per;
    final perText = per == null ? null : '${per.toStringAsFixed(per.abs() < 100 ? 2 : 1)}배';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                point.period,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.65),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              if (point.estimate) ...[
                const SizedBox(width: 4),
                Text(
                  '추정',
                  style: TextStyle(
                    color: accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'EPS',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                epsText,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          if (perText != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'PER',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  perText,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PeerComparisonFooter extends StatelessWidget {
  final StockAiValuation valuation;

  const _PeerComparisonFooter({required this.valuation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasForward = valuation.forwardPer.isNotEmpty;
    final hasSector = valuation.sectorAveragePer.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasForward || hasSector) ...[
            Row(
              children: [
                if (hasForward)
                  Expanded(
                    child: _ValuationKpiBox(
                      label: '선행 PER',
                      value: valuation.forwardPer,
                      color: const Color(0xFF14B8A6),
                    ),
                  ),
                if (hasForward && hasSector) const SizedBox(width: 8),
                if (hasSector)
                  Expanded(
                    child: _ValuationKpiBox(
                      label: '업종 평균 PER',
                      value: valuation.sectorAveragePer,
                      color: const Color(0xFF9B7BFF),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (valuation.peerComparison.isNotEmpty) ...[
            Text(
              '동종업계 비교',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
              ),
              child: Column(
                children: [
                  _PeerHeaderRow(),
                  for (final peer in valuation.peerComparison)
                    _PeerRow(peer: peer),
                ],
              ),
            ),
          ],
          if (valuation.reasoning.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              valuation.reasoning,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.78),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValuationKpiBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ValuationKpiBox({
    required this.label,
    required this.value,
    required this.color,
  });

  static (String headline, String qualifier) _split(String label, String value) {
    final clean = value.trim();
    if (clean.isEmpty) return ('-', '');
    final numRe = RegExp(
      r'-?\d+(?:[.,]\d+)?(?:\s*[~∼\-–]\s*\d+(?:[.,]\d+)?)?\s*(?:배|원|%|점|회|x|X)?',
    );
    final match = numRe.firstMatch(clean);
    if (match == null) {
      return (clean, label.contains('선행') ? '12개월 선행 컨센서스 기준' : '');
    }
    var headline = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'(배|원|%|점|회|x|X)$').hasMatch(headline) &&
        (label.contains('PER') || label.contains('PBR'))) {
      headline = '$headline배';
    }
    var before = clean.substring(0, match.start).trim();
    before = before.replaceAll(RegExp(r'\s*약\s*$'), '').trim();
    before = before.replaceAll(RegExp(r'^약\s+'), '').trim();
    var after = clean.substring(match.end).trim();
    after = after.replaceAll(RegExp(r'^[,\s]+'), '').trim();
    final parts = <String>[];
    if (before.isNotEmpty) parts.add(before);
    if (after.isNotEmpty) parts.add(after);
    var caption = parts.join(' ');
    if (caption.isEmpty && label.contains('선행')) {
      caption = '12개월 선행 컨센서스 기준';
    }
    return (headline, caption);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (headline, qualifier) = _split(label, value);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          if (qualifier.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              qualifier,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeerHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.035),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(9),
          topRight: Radius.circular(9),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              '종목',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'PER',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'PBR',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  final StockAiPeerComparison peer;

  const _PeerRow({required this.peer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.055)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              peer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              peer.per.isEmpty ? '-' : peer.per,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.75),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              peer.pbr.isEmpty ? '-' : peer.pbr,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.75),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetailFooter extends StatelessWidget {
  final StockAiTechnicalDetail detail;

  const _TechnicalDetailFooter({required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSr = detail.support.isNotEmpty || detail.resistance.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '추가 분석',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 11),
          if (hasSr)
            Row(
              children: [
                Expanded(
                  child: _SrBox(
                    label: '지지선 추정',
                    value: detail.support.isEmpty ? '확인 필요' : detail.support,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SrBox(
                    label: '저항선 추정',
                    value: detail.resistance.isEmpty
                        ? '확인 필요'
                        : detail.resistance,
                    color: const Color(0xFFF04452),
                  ),
                ),
              ],
            ),
          if (detail.pattern.isNotEmpty) ...[
            if (hasSr) const SizedBox(height: 10),
            _DetailKv(label: '패턴', value: detail.pattern),
          ],
          if (detail.reasoning.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              detail.reasoning,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.78),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SrBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SrBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailKv extends StatelessWidget {
  final String label;
  final String value;

  const _DetailKv({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.5,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricPanel extends StatelessWidget {
  final List<_MetricRowData> rows;
  final Widget? footer;

  const _MetricPanel({required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          ...rows.map((row) => _MetricRow(row: row, embedded: true)),
          ?footer,
        ],
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
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '최근 ${days.length}거래일 일별 수급',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Text(
                  '순매매량 기준',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 11.5,
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
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
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                headline,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          fontSize: 11,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            '$label선 대비',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.65),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          Text(
            '${positive ? '+' : ''}${gap.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                fontSize: 12.5,
                fontWeight: header ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: -0.1,
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
        fontSize: 12.5,
        fontWeight: header ? FontWeight.w900 : FontWeight.w800,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final _MetricRowData row;
  final bool embedded;

  const _MetricRow({required this.row, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _verdictColor(row.verdict);
    return Container(
      margin: embedded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: embedded ? Colors.transparent : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(embedded ? 0 : 9),
        border: embedded
            ? Border(
                bottom: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.055),
                ),
              )
            : Border.all(color: color.withValues(alpha: 0.11)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.62),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.value,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              row.verdict,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.1,
                height: 1.25,
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

  const _ScoreItem({required this.label, required this.value});
}

class _SignalItem {
  final String title;
  final String value;
  final String body;
  final bool danger;

  const _SignalItem({
    required this.title,
    required this.value,
    required this.body,
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fromCache ? '저장된 분석 사용' : '방금 생성됨',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (generatedText != null)
            Text(
              generatedText!,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/* ── 핵심 재료 (catalysts) ── */
class _CatalystsCard extends StatelessWidget {
  final List<StockAiCatalyst> catalysts;

  const _CatalystsCard({required this.catalysts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('핵심 재료'),
        for (var i = 0; i < catalysts.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < catalysts.length - 1 ? 8 : 0),
            child: _CatalystTile(catalyst: catalysts[i]),
          ),
      ],
    );
  }
}

class _CatalystTile extends StatelessWidget {
  final StockAiCatalyst catalyst;

  const _CatalystTile({required this.catalyst});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _impactColor(catalyst.impact);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 2, color: color),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (catalyst.kind.isNotEmpty)
                      _MetaChip(
                        text: catalyst.kind,
                        color: color,
                        filled: true,
                      ),
                    if (catalyst.impact.isNotEmpty && catalyst.impact != '중립')
                      _MetaChip(text: catalyst.impact, color: color),
                    if (catalyst.timeline.isNotEmpty)
                      _MetaChip(
                        text: catalyst.timeline,
                        color: cs.onSurface.withValues(alpha: 0.42),
                      ),
                    if (catalyst.confidence.isNotEmpty &&
                        catalyst.confidence != '보통')
                      _MetaChip(
                        text: '신뢰도 ${catalyst.confidence}',
                        color: cs.onSurface.withValues(alpha: 0.42),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  catalyst.title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.4,
                    letterSpacing: -0.3,
                  ),
                ),
                if (catalyst.detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _sanitizeDisplayLine(catalyst.detail),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.78),
                      fontSize: 13.5,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const _MetaChip({
    required this.text,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

Color _impactColor(String impact) {
  switch (impact) {
    case '강한긍정':
      return const Color(0xFF10B981);
    case '긍정':
      return const Color(0xFF14B8A6);
    case '부정':
      return const Color(0xFFF59E0B);
    case '강한부정':
      return const Color(0xFFF04452);
    default:
      return const Color(0xFF6B7280);
  }
}

/* ── 시나리오 ── */
class _ScenariosCard extends StatelessWidget {
  final StockAiScenarios scenarios;

  const _ScenariosCard({required this.scenarios});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <(String label, Color color, StockAiScenario? data)>[
      ('강세', const Color(0xFF10B981), scenarios.bull),
      ('기본', const Color(0xFF6B7280), scenarios.base),
      ('약세', const Color(0xFFF04452), scenarios.bear),
    ].where((e) => e.$3 != null).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('시나리오'),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _ScenarioRow(
                  label: entries[i].$1,
                  color: entries[i].$2,
                  scenario: entries[i].$3!,
                  showBorder: i < entries.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  final String label;
  final Color color;
  final StockAiScenario scenario;
  final bool showBorder;

  const _ScenarioRow({
    required this.label,
    required this.color,
    required this.scenario,
    required this.showBorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final probPercent = scenario.probability == null
        ? null
        : (scenario.probability! * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (scenario.priceTarget.isNotEmpty)
                Expanded(
                  child: Text(
                    scenario.priceTarget,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (probPercent != null)
                Text(
                  '$probPercent%',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          if (probPercent != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (probPercent / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: cs.onSurface.withValues(alpha: 0.06),
                color: color,
              ),
            ),
          ],
          if (scenario.trigger.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              scenario.trigger,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.78),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
                letterSpacing: -0.2,
              ),
            ),
          ],
          if (scenario.narrative.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              scenario.narrative,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.65),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.55,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ── 대응전략 (timing) ── */
class _TimingCard extends StatelessWidget {
  final StockAiTiming timing;

  const _TimingCard({required this.timing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actionColor = _actionColor(timing.action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('대응전략'),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (timing.action.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                  color: actionColor.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: actionColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          timing.action,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (timing.actionReason.isNotEmpty)
                        Expanded(
                          child: Text(
                            timing.actionReason,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.82),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (timing.shortTerm.isNotEmpty)
                _TimingBlock(
                  label: '단기 1~2주',
                  text: timing.shortTerm,
                  hasBorder: timing.midTerm.isNotEmpty,
                ),
              if (timing.midTerm.isNotEmpty)
                _TimingBlock(
                  label: '중기 1~3개월',
                  text: timing.midTerm,
                  hasBorder: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimingBlock extends StatelessWidget {
  final String label;
  final String text;
  final bool hasBorder;

  const _TimingBlock({
    required this.label,
    required this.text,
    required this.hasBorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        border: hasBorder
            ? Border(
                bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.82),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.55,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

Color _actionColor(String action) {
  switch (action) {
    case '비중확대':
    case '분할매수':
      return const Color(0xFF10B981);
    case '관망':
    case '판단보류':
      return const Color(0xFFF59E0B);
    case '매수보류':
    case '비중축소':
      return const Color(0xFFF04452);
    default:
      return const Color(0xFF6B7280);
  }
}

/* ── 심층 체크리스트 (sections) ── */
class _SectionsCard extends StatelessWidget {
  final List<StockAiAnalysisSection> sections;

  const _SectionsCard({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('심층 체크리스트'),
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < sections.length - 1 ? 8 : 0),
            child: _SectionTile(section: sections[i]),
          ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final StockAiAnalysisSection section;

  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _sectionAccentColor(section.title);
    final icon = _sectionIcon(section.title);
    final segments = _parseSectionSegments(section.title, section.body);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < segments.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i < segments.length - 1 ? 7 : 0,
                ),
                child: _SectionSegmentRow(
                  segment: segments[i],
                  accent: accent,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionBodySegment {
  final String? label;
  final String text;

  const _SectionBodySegment({this.label, required this.text});
}

class _SectionSegmentRow extends StatelessWidget {
  final _SectionBodySegment segment;
  final Color accent;

  const _SectionSegmentRow({required this.segment, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (segment.label != null) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              segment.label!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 9),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 9, left: 2),
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
        Expanded(
          child: Text(
            segment.text,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.55,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

List<_SectionBodySegment> _parseSectionSegments(String title, String body) {
  final clean = _sanitizeDisplayLine(body).trim();
  if (clean.isEmpty) return const [];
  if (title.contains('CAN SLIM')) {
    final parsed = _parseCanSlimSegments(clean);
    if (parsed.isNotEmpty) return parsed;
  }
  if (title.contains('기술')) {
    final parsed = _parseLabeledSegments(clean, _kTechLabelPattern);
    if (parsed.isNotEmpty) return parsed;
  }
  if (title.contains('확인')) {
    final parsed = _parseSentenceSegments(clean);
    if (parsed.length >= 2) return parsed;
  }
  final sentences = _parseSentenceSegments(clean);
  if (sentences.length >= 2) return sentences;
  return [_SectionBodySegment(text: clean)];
}

final RegExp _kCanSlimPattern = RegExp(
  r'(?:^|\s|,|;|\.|\n)([CANSLIM])\s*[:：\-–—)]\s*',
);

final RegExp _kTechLabelPattern = RegExp(
  r'(이동평균선?|단기[/·]?중기[/·]?장기\s*이동평균|볼린저(?:밴드)?|지지[/·]저항선?|지지선?|저항선?|RSI(?:\(\d+\))?|MACD|패턴|추세|변동성)\s*[:：\-–—]\s*',
);

List<_SectionBodySegment> _parseCanSlimSegments(String body) {
  final matches = _kCanSlimPattern.allMatches(body).toList();
  if (matches.length < 3) return const [];
  final segments = <_SectionBodySegment>[];
  final seenLetters = <String>{};
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final letter = m.group(1)!;
    if (seenLetters.contains(letter)) continue;
    seenLetters.add(letter);
    final start = m.end;
    final end = i + 1 < matches.length ? matches[i + 1].start : body.length;
    final text = body
        .substring(start, end)
        .trim()
        .replaceAll(RegExp(r'[.,;]+$'), '');
    if (text.isEmpty) continue;
    segments.add(_SectionBodySegment(label: letter, text: text));
  }
  return segments;
}

List<_SectionBodySegment> _parseLabeledSegments(String body, RegExp pattern) {
  final matches = pattern.allMatches(body).toList();
  if (matches.length < 2) return const [];
  final segments = <_SectionBodySegment>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final rawLabel = m.group(1)!;
    final label = _normalizeTechLabel(rawLabel);
    final start = m.end;
    final end = i + 1 < matches.length ? matches[i + 1].start : body.length;
    final text = body
        .substring(start, end)
        .trim()
        .replaceAll(RegExp(r'[.,;]+$'), '');
    if (text.isEmpty) continue;
    segments.add(_SectionBodySegment(label: label, text: text));
  }
  return segments;
}

String _normalizeTechLabel(String raw) {
  if (raw.contains('이동평균')) return '이평';
  if (raw.contains('볼린저')) return '볼린저';
  if (raw.contains('지지') && raw.contains('저항')) return '지지/저항';
  if (raw.contains('지지')) return '지지';
  if (raw.contains('저항')) return '저항';
  if (raw.toUpperCase().contains('RSI')) return 'RSI';
  if (raw.toUpperCase().contains('MACD')) return 'MACD';
  if (raw.contains('패턴')) return '패턴';
  if (raw.contains('추세')) return '추세';
  if (raw.contains('변동성')) return '변동성';
  return raw;
}

List<_SectionBodySegment> _parseSentenceSegments(String body) {
  final byNewlines = body
      .split(RegExp(r'[\n\r]+'))
      .map((s) => s.trim().replaceAll(RegExp(r'^[•\-\*\s]+'), ''))
      .where((s) => s.isNotEmpty)
      .toList();
  if (byNewlines.length >= 2) {
    return byNewlines.map((s) => _SectionBodySegment(text: s)).toList();
  }
  final bySentence = body
      .split(RegExp(r'(?<=[.!?])\s+(?=[가-힣A-Za-z0-9])'))
      .map((s) => s.trim().replaceAll(RegExp(r'^[•\-\*\s]+'), ''))
      .where((s) => s.isNotEmpty)
      .toList();
  if (bySentence.isEmpty) return [_SectionBodySegment(text: body)];
  return bySentence.map((s) => _SectionBodySegment(text: s)).toList();
}

IconData _sectionIcon(String title) {
  if (title.contains('CAN SLIM')) return Icons.checklist_rounded;
  if (title.contains('기술')) return Icons.show_chart_rounded;
  if (title.contains('재무')) return Icons.account_balance_rounded;
  if (title.contains('수익률')) return Icons.timeline_rounded;
  if (title.contains('실적') || title.contains('서프라이즈')) {
    return Icons.bolt_rounded;
  }
  if (title.contains('공시')) return Icons.description_rounded;
  if (title.contains('뉴스')) return Icons.article_rounded;
  if (title.contains('확인')) return Icons.flag_rounded;
  return Icons.list_alt_rounded;
}

Color _sectionAccentColor(String title) {
  if (title.contains('CAN SLIM')) return const Color(0xFF6366F1);
  if (title.contains('기술')) return const Color(0xFF10B981);
  if (title.contains('재무')) return const Color(0xFF14B8A6);
  if (title.contains('수익률')) return const Color(0xFF0EA5E9);
  if (title.contains('실적') || title.contains('서프라이즈')) {
    return const Color(0xFFF59E0B);
  }
  if (title.contains('공시')) return const Color(0xFF8B5CF6);
  if (title.contains('뉴스')) return const Color(0xFF38BDF8);
  if (title.contains('확인')) return const Color(0xFFF04452);
  return const Color(0xFF6B7280);
}

/* ── 리스크 상세 (risksDetailed) ── */
class _RisksDetailedCard extends StatelessWidget {
  final List<StockAiRiskDetail> risks;

  const _RisksDetailedCard({required this.risks});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('리스크 상세'),
        for (var i = 0; i < risks.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < risks.length - 1 ? 8 : 0),
            child: _RiskTile(risk: risks[i]),
          ),
      ],
    );
  }
}

class _RiskTile extends StatelessWidget {
  final StockAiRiskDetail risk;

  const _RiskTile({required this.risk});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final severityColor = _severityColor(risk.severity);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 2, color: severityColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (risk.category.isNotEmpty)
                      _MetaChip(
                        text: risk.category,
                        color: severityColor,
                        filled: true,
                      ),
                    if (risk.severity.isNotEmpty)
                      _MetaChip(
                        text: '심각도 ${risk.severity}',
                        color: severityColor,
                      ),
                    if (risk.probability.isNotEmpty)
                      _MetaChip(
                        text: '가능성 ${risk.probability}',
                        color: cs.onSurface.withValues(alpha: 0.42),
                      ),
                  ],
                ),
                if (risk.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    risk.description,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.55,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
                if (risk.mitigant.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: severityColor.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '대응  ',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            risk.mitigant,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.75),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _severityColor(String severity) {
  switch (severity) {
    case '높음':
      return const Color(0xFFF04452);
    case '보통':
      return const Color(0xFFF59E0B);
    case '낮음':
      return const Color(0xFF10B981);
    default:
      return const Color(0xFF6B7280);
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
  final sector = (analysis.valuation?.sectorAveragePer ?? '').trim();
  final source = sector.isNotEmpty ? sector : analysis.peerPerAverage;
  final text = StockAiAnalysisResultScreen.cleanText(source);
  if (text.isEmpty) return '업종 평균 확인 필요';
  return _sanitizeDisplayLine(text);
}

String _peerPerShort(StockAiAnalysisResult analysis) {
  final sector = (analysis.valuation?.sectorAveragePer ?? '').trim();
  final source = sector.isNotEmpty ? sector : analysis.peerPerAverage;
  final text = StockAiAnalysisResultScreen.cleanText(source);
  if (text.isEmpty) return '업종 평균 -';
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
  final number = match?.group(1);
  if (number == null) return '업종 평균';
  return '업종 $number';
}

List<String> _relatedPeers(StockAiAnalysisResult analysis) {
  final seen = <String>{};
  final peers = <String>[];
  void add(String value) {
    final text = StockAiAnalysisResultScreen.cleanText(value);
    if (text.isEmpty || text == '-') return;
    if (seen.add(text)) peers.add(text);
  }

  for (final peer in analysis.themePeers) {
    add(peer);
  }
  for (final peer in analysis.valuation?.peerComparison ?? const []) {
    add(peer.name);
  }
  return peers.take(8).toList();
}

String _themeDisplayText(String value) {
  var text = StockAiAnalysisResultScreen.cleanText(value);
  text = text.replaceAll(RegExp(r'(근거|이유|확인되는 강도|불확실성)\s*[:：].*$'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return value;
  return text;
}

String _newsDisplayText(StockAiAnalysisResult analysis) {
  // AI가 요약한 뉴스 방향성을 우선 사용. 빈 경우에만 fallback으로 헤드라인 1~2개.
  final newsText = analysis.news.trim();
  if (newsText.isNotEmpty) return newsText;
  final titles = analysis.sourceNews
      .map((item) => item.title.trim())
      .where((title) => title.isNotEmpty)
      .take(2)
      .toList();
  return titles.join('\n');
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

String _formatWon(double value) {
  return '${NumberFormat('#,###').format(value.round())}원';
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
  // 비공개/placeholder/미확인 변수 등 메타 표현 제거
  text = text.replaceAll(RegExp(r'\s*\(\s*(정량적?\s*내용\s*)?비공개\s*\)\s*'), ' ');
  text = text.replaceAll(RegExp(r'\s*\(\s*자세한\s*수치는?\s*비공개\s*\)\s*'), ' ');
  text = text.replaceAll(RegExp(r'\s*\(\s*비공개\s*\)\s*'), ' ');
  text = text.replaceAll(RegExp(r'\s*미확인\s*변수[^.\n]*\.?'), '');
  text = text.replaceAllMapped(
    RegExp(
      r'(^|[.!?\n]\s*)(핵심\s*원인(?:은)?|주요\s*원인|근거\s*뉴스\s*/?\s*공시|거래\s*/?\s*가격\s*반응|설명\s*한계)\s*[:：]?\s*',
    ),
    (match) => match.group(1) ?? '',
  );
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
