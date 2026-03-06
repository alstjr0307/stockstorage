import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/announcement.dart';
import '../models/market_analysis.dart';
import '../models/stock_pick.dart';
import '../services/fcm_direct_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          '관리자 패널',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80),
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
          tabs: const [
            Tab(text: '종목 등록'),
            Tab(text: '목록 관리'),
            Tab(text: '공지사항'),
            Tab(text: '시황 분석'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _UploadTab(),
          _ManageTab(),
          _AnnouncementTab(),
          _MarketAnalysisAdminTab(),
        ],
      ),
    );
  }
}

// ─── 등록 탭 ───────────────────────────────────────────────────────────────

class _UploadTab extends StatefulWidget {
  const _UploadTab({this.editPick});
  final StockPick? editPick;

  @override
  State<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<_UploadTab> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  late final TextEditingController _tickerController;
  late final TextEditingController _nameController;
  late final TextEditingController _buyPriceController;
  late final TextEditingController _targetPriceController;
  late final TextEditingController _reasonController;

  String _category = '단기';
  String _market = 'KS';
  bool _isPremium = false;
  bool _isLoading = false;

  bool get _isEdit => widget.editPick != null;

  @override
  void initState() {
    super.initState();
    final p = widget.editPick;
    _tickerController = TextEditingController(text: p?.ticker ?? '');
    _nameController = TextEditingController(text: p?.name ?? '');
    _buyPriceController =
        TextEditingController(text: p != null ? p.buyPrice.toInt().toString() : '');
    _targetPriceController =
        TextEditingController(text: p != null ? p.targetPrice.toInt().toString() : '');
    _reasonController = TextEditingController(text: p?.reason ?? '');
    if (p != null) {
      _category = p.category;
      _market = p.market;
      _isPremium = p.isPremium;
    }
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _nameController.dispose();
    _buyPriceController.dispose();
    _targetPriceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StockSearchField(
            initialTicker: _tickerController.text,
            initialName: _nameController.text,
            onSelected: (ticker, name, market) {
              setState(() {
                _tickerController.text = ticker;
                _nameController.text = name;
                _market = market;
              });
            },
          ),
          const SizedBox(height: 14),
          _buildField('매수가', _buyPriceController, hint: '70000', isNumber: true),
          const SizedBox(height: 14),
          _buildField('목표가', _targetPriceController, hint: '85000', isNumber: true),
          const SizedBox(height: 14),
          _buildField('매수 근거', _reasonController,
              hint: '매수 근거를 입력하세요...', maxLines: 5),
          const SizedBox(height: 20),
          Text('투자 기간',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: ['단기', '장기'].map((cat) {
              final isSelected = _category == cat;
              return GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF1A2035),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4ADE80)
                          : Colors.white12,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.black : Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2035),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title:
                  Text('프리미엄 콘텐츠', style: GoogleFonts.inter(color: Colors.white70)),
              subtitle: Text('로그인 사용자만 상세 열람 가능',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
              value: _isPremium,
              activeThumbColor: const Color(0xFFFFD700),
              onChanged: (val) => setState(() => _isPremium = val),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4ADE80),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(
                      _isEdit ? '수정하기' : '등록하기',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType:
              isNumber ? TextInputType.number : TextInputType.multiline,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF1A2035),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF4ADE80), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (val) =>
              val == null || val.isEmpty ? '$label을 입력하세요' : null,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final pick = StockPick(
        id: widget.editPick?.id ?? '',
        ticker: _tickerController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        buyPrice:
            double.parse(_buyPriceController.text.replaceAll(',', '')),
        targetPrice:
            double.parse(_targetPriceController.text.replaceAll(',', '')),
        reason: _reasonController.text.trim(),
        category: _category,
        market: _market,
        isPremium: _isPremium,
        createdAt: widget.editPick?.createdAt ?? DateTime.now(),
      );

      if (_isEdit) {
        await _firestoreService.updateStockPick(pick);
      } else {
        await _firestoreService.addStockPick(pick);
        FcmDirectService.sendTopicNotification(
          title: '📈 새 추천 종목',
          body: '${pick.name}(${pick.ticker}) 종목이 새로 등록되었습니다. 지금 확인해보세요!',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pick.name} ${_isEdit ? '수정' : '등록'} 완료!',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFF4ADE80),
          ),
        );
        if (_isEdit) {
          Navigator.pop(context);
        } else {
          _formKey.currentState!.reset();
          _tickerController.clear();
          _nameController.clear();
          _buyPriceController.clear();
          _targetPriceController.clear();
          _reasonController.clear();
          setState(() {
            _category = '단기';
            _isPremium = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('오류: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ─── 관리 탭 ───────────────────────────────────────────────────────────────

class _ManageTab extends StatelessWidget {
  const _ManageTab();

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<List<StockPick>>(
      stream: firestoreService.getStockPicks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4ADE80)));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('오류: ${snapshot.error}',
                style: GoogleFonts.inter(color: Colors.redAccent)),
          );
        }
        final picks = snapshot.data ?? [];
        if (picks.isEmpty) {
          return Center(
            child: Text('등록된 종목이 없습니다',
                style: GoogleFonts.inter(color: Colors.white38)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: picks.length,
          itemBuilder: (context, index) {
            final pick = picks[index];
            return _ManageCard(
              pick: pick,
              firestoreService: firestoreService,
            );
          },
        );
      },
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({required this.pick, required this.firestoreService});
  final StockPick pick;
  final FirestoreService firestoreService;

  @override
  Widget build(BuildContext context) {
    final categoryColors = {
      '단기': Colors.orangeAccent,
      '장기': Colors.purpleAccent,
    };
    final catColor = categoryColors[pick.category] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pick.isPremium
              ? const Color(0xFFFFD700).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          // 티커 + 이름
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      pick.ticker,
                      style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pick.category,
                        style: GoogleFonts.inter(
                            color: catColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (pick.isPremium) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.star,
                          color: Color(0xFFFFD700), size: 13),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pick.name,
                  style:
                      GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  '매수 ${pick.buyPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원  →  목표 ${pick.targetPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원',
                  style:
                      GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // 종료 버튼 (active 상태일 때만)
          if (!pick.isCompleted)
            IconButton(
              icon: const Icon(Icons.check_circle_outline,
                  color: Colors.orangeAccent, size: 20),
              tooltip: '종료 처리',
              onPressed: () => _confirmClose(context),
            ),
          // 편집 버튼
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: Color(0xFF4ADE80), size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _EditScreen(pick: pick),
              ),
            ),
          ),
          // 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context) async {
    final controller = TextEditingController();
    final closedPrice = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('종료 처리',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pick.name} (${pick.ticker})\n실제 종료가를 입력하세요.',
                style: GoogleFonts.inter(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                hintText: '종료가',
                hintStyle: GoogleFonts.inter(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF0A0E1A),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소',
                style: GoogleFonts.inter(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              final price =
                  double.tryParse(controller.text.replaceAll(',', ''));
              Navigator.pop(context, price);
            },
            child: Text('종료',
                style: GoogleFonts.inter(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (closedPrice != null) {
      try {
        await firestoreService.closeStockPick(pick.id, closedPrice);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${pick.name} 종료 처리됨', style: GoogleFonts.inter()),
            backgroundColor: Colors.orangeAccent,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('오류: $e'),
              backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('삭제 확인',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          '${pick.name}(${pick.ticker})을 삭제하시겠습니까?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: GoogleFonts.inter(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제',
                style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await firestoreService.deleteStockPick(pick.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${pick.name} 삭제됨', style: GoogleFonts.inter()),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('오류: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }
}

// ─── 주식 검색 필드 ────────────────────────────────────────────────────────

class _StockSearchField extends StatefulWidget {
  final String initialTicker;
  final String initialName;
  final void Function(String ticker, String name, String market) onSelected;

  const _StockSearchField({
    required this.initialTicker,
    required this.initialName,
    required this.onSelected,
  });

  @override
  State<_StockSearchField> createState() => _StockSearchFieldState();
}

class _StockSearchFieldState extends State<_StockSearchField> {
  late final TextEditingController _searchController;
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<StockSearchResult> _results = [];
  Timer? _debounce;
  bool _loading = false;
  bool _selected = false; // 선택 완료 상태

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTicker.isNotEmpty
        ? '${widget.initialTicker}  ${widget.initialName}'
        : '';
    _searchController = TextEditingController(text: initial);
    if (widget.initialTicker.isNotEmpty) _selected = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _selected = false;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await StockPriceService.searchStocks(query);
    if (!mounted) return;
    setState(() { _results = results; _loading = false; });
    if (results.isNotEmpty) _showOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(builder: (_) => _buildDropdown());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _onSelect(StockSearchResult r) {
    _selected = true;
    _searchController.text = '${r.ticker}  ${r.name}';
    _removeOverlay();
    widget.onSelected(r.ticker, r.name, r.market);
  }

  Widget _buildDropdown() {
    return Positioned(
      width: 300,
      child: CompositedTransformFollower(
        link: _layerLink,
        offset: const Offset(0, 56),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2A40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16)],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final marketColor = switch (r.market) {
                  'KS' => Colors.blueAccent,
                  'KQ' => Colors.purpleAccent,
                  _ => Colors.orangeAccent,
                };
                final marketLabel = switch (r.market) {
                  'KS' => 'KOSPI',
                  'KQ' => 'KOSDAQ',
                  _ => 'US',
                };
                return InkWell(
                  onTap: () => _onSelect(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: marketColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(marketLabel,
                              style: GoogleFonts.inter(color: marketColor, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(r.ticker,
                                  style: GoogleFonts.robotoMono(color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('종목 검색',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _layerLink,
          child: TextFormField(
            controller: _searchController,
            style: GoogleFonts.inter(color: Colors.white),
            onChanged: _onChanged,
            onTap: () {
              if (!_selected && _searchController.text.isNotEmpty) {
                _search(_searchController.text.trim());
              }
            },
            decoration: InputDecoration(
              hintText: '종목명 또는 티커 검색 (예: 삼성전자, AAPL)',
              hintStyle: GoogleFonts.inter(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF1A2035),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80))),
                    )
                  : _selected
                      ? const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 18)
                      : const Icon(Icons.search, color: Colors.white24, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            validator: (_) => !_selected ? '종목을 검색하여 선택하세요' : null,
          ),
        ),
      ],
    );
  }
}

// ─── 편집 화면 ─────────────────────────────────────────────────────────────

class _EditScreen extends StatelessWidget {
  const _EditScreen({required this.pick});
  final StockPick pick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '종목 수정',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: _UploadTab(editPick: pick),
    );
  }
}

// ─── 공지사항 탭 ───────────────────────────────────────────────────────────

class _AnnouncementTab extends StatefulWidget {
  const _AnnouncementTab();

  @override
  State<_AnnouncementTab> createState() => _AnnouncementTabState();
}

class _AnnouncementTabState extends State<_AnnouncementTab> {
  final _fs = FirestoreService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _isPinned = false;
  bool _isLoading = false;

  // 편집 중인 공지 (null이면 신규 등록)
  Announcement? _editing;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _startEdit(Announcement a) {
    setState(() {
      _editing = a;
      _titleCtrl.text = a.title;
      _bodyCtrl.text = a.body;
      _isPinned = a.isPinned;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _isPinned = false;
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final a = Announcement(
        id: _editing?.id ?? '',
        title: title,
        body: body,
        isPinned: _isPinned,
        createdAt: _editing?.createdAt ?? DateTime.now(),
      );
      if (_editing != null) {
        await _fs.updateAnnouncement(a);
      } else {
        await _fs.addAnnouncement(a);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing != null ? '공지 수정 완료' : '공지 등록 완료',
              style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFF4ADE80),
        ));
        _cancelEdit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('오류: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('삭제 확인',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text('공지 "${a.title}"를 삭제하시겠습니까?',
            style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소', style: GoogleFonts.inter(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('삭제',
                  style: GoogleFonts.inter(
                      color: Colors.redAccent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) await _fs.deleteAnnouncement(a.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 입력 폼 ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1A2035),
            border: Border(bottom: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editing != null ? '공지 수정' : '공지 등록',
                  style: GoogleFonts.inter(
                      color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _inputDeco('제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _inputDeco('본문'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Switch(
                    value: _isPinned,
                    activeThumbColor: const Color(0xFF4ADE80),
                    onChanged: (v) => setState(() => _isPinned = v),
                  ),
                  Text('상단 고정',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  if (_editing != null)
                    TextButton(
                      onPressed: _cancelEdit,
                      child: Text('취소',
                          style: GoogleFonts.inter(color: Colors.white38)),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4ADE80),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text(_editing != null ? '수정' : '등록',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── 공지 목록 ──
        Expanded(
          child: StreamBuilder<List<Announcement>>(
            stream: _fs.getAnnouncements(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4ADE80)));
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('등록된 공지가 없습니다',
                        style: GoogleFonts.inter(color: Colors.white38)));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2035),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: a.isPinned
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (a.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.push_pin,
                                color: Color(0xFF4ADE80), size: 14),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(a.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF4ADE80), size: 18),
                          onPressed: () => _startEdit(a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 18),
                          onPressed: () => _delete(a),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF0A0E1A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

// ─── 시황 분석 관리 탭 ──────────────────────────────────────────────────────

class _MarketAnalysisAdminTab extends StatefulWidget {
  const _MarketAnalysisAdminTab();

  @override
  State<_MarketAnalysisAdminTab> createState() =>
      _MarketAnalysisAdminTabState();
}

class _MarketAnalysisAdminTabState extends State<_MarketAnalysisAdminTab> {
  final _fs = FirestoreService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _isLoading = false;
  MarketAnalysis? _editing;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _startEdit(MarketAnalysis a) {
    setState(() {
      _editing = a;
      _titleCtrl.text = a.title;
      _bodyCtrl.text = a.body;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _titleCtrl.clear();
      _bodyCtrl.clear();
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final a = MarketAnalysis(
        id: _editing?.id ?? '',
        title: title,
        body: body,
        createdAt: _editing?.createdAt ?? DateTime.now(),
      );
      if (_editing != null) {
        await _fs.updateMarketAnalysis(a);
      } else {
        await _fs.addMarketAnalysis(a);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing != null ? '수정 완료' : '등록 완료',
              style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFF4ADE80),
        ));
        _cancelEdit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('오류: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(MarketAnalysis a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('삭제 확인',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text('"${a.title}"를 삭제하시겠습니까?',
            style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소',
                  style: GoogleFonts.inter(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('삭제',
                  style: GoogleFonts.inter(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) await _fs.deleteMarketAnalysis(a.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 입력 폼 ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1A2035),
            border: Border(bottom: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editing != null ? '시황 분석 수정' : '시황 분석 등록',
                  style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _inputDeco('제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                maxLines: 5,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: _inputDeco('본문'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  if (_editing != null)
                    TextButton(
                      onPressed: _cancelEdit,
                      child: Text('취소',
                          style:
                              GoogleFonts.inter(color: Colors.white38)),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4ADE80),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text(_editing != null ? '수정' : '등록',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── 목록 ──
        Expanded(
          child: StreamBuilder<List<MarketAnalysis>>(
            stream: _fs.getMarketAnalyses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF4ADE80)));
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('등록된 시황 분석이 없습니다',
                        style:
                            GoogleFonts.inter(color: Colors.white38)));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2035),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(a.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: Colors.white38,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF4ADE80), size: 18),
                          onPressed: () => _startEdit(a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 18),
                          onPressed: () => _delete(a),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF0A0E1A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
