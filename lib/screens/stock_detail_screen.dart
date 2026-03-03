import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/comment.dart';
import '../models/stock_pick.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';

class StockDetailScreen extends StatefulWidget {
  final StockPick pick;
  const StockDetailScreen({super.key, required this.pick});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  PriceResult? _livePrice;
  bool _loadingPrice = true;
  List<double> _chartData = [];
  bool _loadingChart = true;

  final _commentController = TextEditingController();
  final _memoController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _submitting = false;
  bool _memoSaving = false;
  bool _memoChanged = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    AdService.instance.showInterstitialIfReady();
    AdService.instance.loadInterstitial();
    _fetchPrice();
    _fetchChart();
    _loadMemo();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadMemo() async {
    final user = _currentUser;
    if (user == null) return;
    final text = await _firestoreService.getMemo(user.uid, widget.pick.id);
    if (mounted && text != null) {
      _memoController.text = text;
    }
  }

  Future<void> _saveMemo() async {
    final user = _currentUser;
    if (user == null) return;
    setState(() => _memoSaving = true);
    await _firestoreService.saveMemo(
        user.uid, widget.pick.id, _memoController.text.trim());
    if (mounted) {
      setState(() {
        _memoSaving = false;
        _memoChanged = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('메모가 저장되었습니다',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchPrice() async {
    final result = await StockPriceService.fetchPrice(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted) setState(() { _livePrice = result; _loadingPrice = false; });
  }

  Future<void> _fetchChart() async {
    final data = await StockPriceService.fetchHistory(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted) setState(() { _chartData = data; _loadingChart = false; });
  }

  void _shareStock() {
    final pick = widget.pick;
    final returnRate = pick.returnRate;
    final isPositive = returnRate >= 0;
    final text = '📈 [StockStorage] ${pick.name} (${pick.ticker})\n\n'
        '매수가: ${_formatPrice(pick.buyPrice, pick.market)}\n'
        '목표가: ${_formatPrice(pick.targetPrice, pick.market)}\n'
        '예상 수익률: ${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%\n'
        '투자 기간: ${pick.category}\n\n'
        '매수 근거:\n${pick.reason}\n\n'
        'StockStorage 앱에서 더 많은 매수 관심종목을 확인하세요!';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final formatter = NumberFormat('#,###');

    final livePrice = _livePrice?.price;
    final returnRate = livePrice != null
        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
        : pick.returnRate;
    final isPositive = returnRate >= 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          pick.ticker,
          style: GoogleFonts.robotoMono(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white54, size: 20),
            onPressed: _shareStock,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white38, size: 20),
            onPressed: () {
              setState(() { _loadingPrice = true; _loadingChart = true; });
              _fetchPrice();
              _fetchChart();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // 종목 헤더
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pick.name,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _marketBadge(pick.market),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('yyyy.MM.dd HH:mm').format(pick.createdAt),
                            style: GoogleFonts.inter(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isPositive
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                              : Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                          color: isPositive
                              ? const Color(0xFF4ADE80)
                              : Colors.redAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '매수가 대비',
                      style: GoogleFonts.inter(
                          color: Colors.white24, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 실시간 현재가 카드
            _livePriceCard(pick, formatter),
            const SizedBox(height: 12),

            // 1개월 차트
            _chartCard(),

            // 매수가 / 목표가 카드
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _priceItem(
                      '매수가',
                      _formatPrice(pick.buyPrice, pick.market),
                      Colors.white70,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: _priceItem(
                      '목표가',
                      _formatPrice(pick.targetPrice, pick.market),
                      const Color(0xFF4ADE80),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 카테고리
            _sectionLabel('투자 기간'),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(pick.category,
                  style: GoogleFonts.inter(color: Colors.white70)),
            ),
            const SizedBox(height: 20),

            // 매수 근거
            _sectionLabel('매수 근거'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                pick.reason,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.8),
              ),
            ),
            const SizedBox(height: 24),

            // 투자 메모 섹션
            if (_currentUser != null) ...[
              _memoSection(),
              const SizedBox(height: 24),
            ],

            // 코멘트 섹션
            _commentSection(),
            const SizedBox(height: 8),
          ],
        ),
      ),
          ),
          _commentInput(),
        ],
      ),
    );
  }

  Widget _chartCard() {
    if (_loadingChart) {
      return Container(
        height: 140,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF4ADE80)),
        ),
      );
    }
    if (_chartData.length < 2) return const SizedBox.shrink();

    final spots = _chartData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minY = _chartData.reduce((a, b) => a < b ? a : b);
    final maxY = _chartData.reduce((a, b) => a > b ? a : b);
    final isPositive = _chartData.last >= _chartData.first;
    final lineColor =
        isPositive ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Container(
      height: 140,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1개월 차트',
            style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY * 0.995,
                maxY: maxY * 1.005,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: lineColor,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.08),
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

  Widget _livePriceCard(StockPick pick, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Color(0xFF4ADE80), size: 18),
          const SizedBox(width: 10),
          Text('현재가',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
          const SizedBox(width: 12),
          if (_loadingPrice)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF4ADE80)),
            )
          else if (_livePrice == null)
            Text('조회 불가',
                style: GoogleFonts.inter(color: Colors.white24, fontSize: 13))
          else ...[
            Text(
              _livePrice!.formattedPrice,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _livePrice!.formattedChange,
              style: GoogleFonts.inter(
                color: _livePrice!.isUp
                    ? const Color(0xFF4ADE80)
                    : Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '3분 캐시',
            style: GoogleFonts.inter(color: Colors.white12, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _marketBadge(String market) {
    final info = switch (market) {
      'KS' => ('KOSPI', Colors.blueAccent),
      'KQ' => ('KOSDAQ', Colors.purpleAccent),
      _ => ('US', Colors.orangeAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: info.$2.withValues(alpha: 0.4)),
      ),
      child: Text(info.$1,
          style: GoogleFonts.inter(
              color: info.$2, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  String _formatPrice(double price, String market) {
    final formatter = NumberFormat('#,###');
    if (market == 'US') return '\$${price.toStringAsFixed(2)}';
    return '₩${formatter.format(price.toInt())}';
  }

  Widget _priceItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.inter(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5),
    );
  }

  // ── 투자 메모 ─────────────────────────────────────────────────────────────
  Widget _memoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('내 투자 메모'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _memoChanged
                  ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _memoController,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.7),
                maxLines: 5,
                minLines: 3,
                onChanged: (_) {
                  if (!_memoChanged) setState(() => _memoChanged = true);
                },
                decoration: InputDecoration(
                  hintText: '이 종목에 대한 나만의 메모를 남겨보세요\n(매수 이유, 목표, 주의사항 등)',
                  hintStyle: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 13, height: 1.6),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              if (_memoChanged)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ADE80),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _memoSaving ? null : _saveMemo,
                      child: _memoSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : Text('저장',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 코멘트 목록 ──────────────────────────────────────────────────────────
  Widget _commentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('코멘트'),
        const SizedBox(height: 10),
        StreamBuilder<List<Comment>>(
          stream: _firestoreService.getComments(widget.pick.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4ADE80)),
                ),
              );
            }
            final comments = snapshot.data ?? [];
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '첫 번째 코멘트를 남겨보세요',
                  style: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 13),
                ),
              );
            }
            return Column(
              children: comments
                  .map((c) => _commentItem(c))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _commentItem(Comment comment) {
    final isOwn = _currentUser?.uid == comment.uid;
    final isAdmin = _currentUser?.uid == AuthService.adminUid;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                comment.displayName,
                style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                timeago.format(comment.createdAt, locale: 'ko'),
                style: GoogleFonts.inter(
                    color: Colors.white24, fontSize: 11),
              ),
              const Spacer(),
              if (isOwn || isAdmin)
                GestureDetector(
                  onTap: () => _firestoreService.deleteComment(
                      widget.pick.id, comment.id),
                  child: const Icon(Icons.close,
                      color: Colors.white24, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.text,
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── 코멘트 입력창 (하단 고정) ────────────────────────────────────────────
  Widget _commentInput() {
    final user = _currentUser;
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: const Color(0xFF0A0E1A),
        child: Text(
          '로그인 후 코멘트를 남길 수 있습니다',
          style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComment(user),
              decoration: InputDecoration(
                hintText: '코멘트를 입력하세요...',
                hintStyle:
                    GoogleFonts.inter(color: Colors.white24, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF1A2035),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _submitting ? null : () => _submitComment(user),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.black, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment(User user) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final nickname = await _firestoreService.getNickname(user.uid)
        ?? user.email?.split('@').first
        ?? '익명';
    await _firestoreService.addComment(
      widget.pick.id,
      Comment(
        id: '',
        uid: user.uid,
        displayName: nickname,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
    _commentController.clear();
    if (mounted) setState(() => _submitting = false);
  }
}
