import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/announcement.dart';
import '../models/market_analysis.dart';
import '../models/stock_pick.dart';
import '../services/fcm_direct_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../widgets/stock_search_field.dart';
import 'write_market_analysis_screen.dart';

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
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '관리자 패널',
          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
          isScrollable: true,
          tabs: const [
            Tab(text: '종목 등록'),
            Tab(text: '목록 관리'),
            Tab(text: '공지사항'),
            Tab(text: '시황 분석'),
            Tab(text: '알림 발송'),
            Tab(text: '유저 목록'),
            Tab(text: '신고 관리'),
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
          _PushNotificationTab(),
          _UsersTab(),
          _ReportsTab(),
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

  String _market = 'KS';
  bool _isPremium = false;
  bool _isLoading = false;
  DateTime? _earningsDate;

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
      _market = p.market;
      _isPremium = p.isPremium;
      _earningsDate = p.earningsDate;
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
          StockSearchField(
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
          const SizedBox(height: 14),
          _buildEarningsDatePicker(),
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
                  Text('로그인 후 열람 가능', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
              subtitle: Text('로그인 사용자만 상세 열람 가능',
                  style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 12)),
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
                backgroundColor: const Color(0xFF10B981),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType:
              isNumber ? TextInputType.number : TextInputType.multiline,
          style: GoogleFonts.inter(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.24)),
            filled: true,
            fillColor: const Color(0xFF1A2035),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF10B981), width: 1.5),
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

  Widget _buildEarningsDatePicker() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('실적 발표일',
            style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 12)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _earningsDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: const Color(0xFF10B981),
                    onPrimary: Colors.black,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _earningsDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2035),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    color: cs.onSurface.withValues(alpha: 0.38), size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _earningsDate != null
                        ? DateFormat('yyyy년 MM월 dd일').format(_earningsDate!)
                        : '선택사항',
                    style: GoogleFonts.inter(
                      color: _earningsDate != null
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_earningsDate != null)
                  GestureDetector(
                    onTap: () => setState(() => _earningsDate = null),
                    child: Icon(Icons.close,
                        color: cs.onSurface.withValues(alpha: 0.38), size: 16),
                  ),
              ],
            ),
          ),
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
        category: '',
        market: _market,
        isPremium: _isPremium,
        createdAt: widget.editPick?.createdAt ?? DateTime.now(),
        earningsDate: _earningsDate,
      );

      if (_isEdit) {
        await _firestoreService.updateStockPick(pick);
      } else {
        await _firestoreService.addStockPick(pick);
        FcmDirectService.sendTopicNotification(
          title: '📈 새 추천 종목',
          body: '새 추천 종목이 등록되었습니다. 지금 확인해보세요!',
        ).catchError((_) {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pick.name} ${_isEdit ? '수정' : '등록'} 완료!',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFF10B981),
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
            _isPremium = false;
            _earningsDate = null;
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
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<StockPick>>(
      stream: firestoreService.getStockPicks(),
      builder: (context, activeSnap) {
        return StreamBuilder<List<StockPick>>(
          stream: firestoreService.getCompletedPicks(),
          builder: (context, completedSnap) {
            if (activeSnap.connectionState == ConnectionState.waiting ||
                completedSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF10B981)));
            }

            final activePicks = activeSnap.data ?? [];
            final completedPicks = completedSnap.data ?? [];

            if (activePicks.isEmpty && completedPicks.isEmpty) {
              return Center(
                child: Text('등록된 종목이 없습니다',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.38))),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (activePicks.isNotEmpty) ...[
                  _sectionLabel(cs, '진행 중 (${activePicks.length})'),
                  const SizedBox(height: 8),
                  ...activePicks.map((pick) => _ManageCard(
                        pick: pick,
                        firestoreService: firestoreService,
                      )),
                ],
                if (completedPicks.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionLabel(cs, '종료 종목 (${completedPicks.length})'),
                  const SizedBox(height: 8),
                  ...completedPicks.map((pick) => _ManageCard(
                        pick: pick,
                        firestoreService: firestoreService,
                      )),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
          color: cs.onSurface.withValues(alpha: 0.45),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5),
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({required this.pick, required this.firestoreService});
  final StockPick pick;
  final FirestoreService firestoreService;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pick.isPremium
              ? const Color(0xFFFFD700).withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
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
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
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
                      GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12),
                ),
                Text(
                  '매수 ${pick.buyPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원  →  목표 ${pick.targetPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원',
                  style:
                      GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 11),
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
          // 편집 버튼 (진행 중만)
          if (!pick.isCompleted)
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: Color(0xFF10B981), size: 20),
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
    // 현재가 자동 fetch 후 pre-fill
    StockPriceService.fetchPrice(pick.ticker, pick.market).then((result) {
      if (result != null && controller.text.isEmpty) {
        final val = pick.market == 'US'
            ? result.price.toStringAsFixed(2)
            : result.price.toInt().toString();
        controller.text = val;
      }
    });
    final closedPrice = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('종료 처리',
            style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pick.name} (${pick.ticker})\n실제 종료가를 입력하세요.',
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: '종료가',
                hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
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
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38))),
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
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
          '${pick.name}(${pick.ticker})을 삭제하시겠습니까?',
          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38))),
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

// ─── 편집 화면 ─────────────────────────────────────────────────────────────

class _EditScreen extends StatelessWidget {
  const _EditScreen({required this.pick});
  final StockPick pick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '종목 수정',
          style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
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
          backgroundColor: const Color(0xFF10B981),
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
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
        content: Text('공지 "${a.title}"를 삭제하시겠습니까?',
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)))),
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
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editing != null ? '공지 수정' : '공지 등록',
                  style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                decoration: _inputDeco(context, '제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                decoration: _inputDeco(context, '본문'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Switch(
                    value: _isPinned,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _isPinned = v),
                  ),
                  Text('상단 고정',
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
                  const Spacer(),
                  if (_editing != null)
                    TextButton(
                      onPressed: _cancelEdit,
                      child: Text('취소',
                          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38))),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
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
                    child: CircularProgressIndicator(color: Color(0xFF10B981)));
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('등록된 공지가 없습니다',
                        style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38))));
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
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (a.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.push_pin,
                                color: Color(0xFF10B981), size: 14),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: GoogleFonts.inter(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(a.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF10B981), size: 18),
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

  InputDecoration _inputDeco(BuildContext context, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.24)),
        filled: true,
        fillColor: const Color(0xFF0A0E1A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF10B981), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
  }
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

  Future<void> _openWrite([MarketAnalysis? editing]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WriteMarketAnalysisScreen(editing: editing),
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  Future<void> _delete(MarketAnalysis a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text('삭제 확인',
            style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
        content: Text('"${a.title}"를 삭제하시겠습니까?',
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소',
                  style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)))),
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
        // 작성 버튼
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            border: Border(
                bottom: BorderSide(
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12))),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openWrite(),
              icon: const Icon(Icons.add, size: 20),
              label: Text('새 시황 분석 작성',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ),
        // 목록
        Expanded(
          child: StreamBuilder<List<MarketAnalysis>>(
            stream: _fs.getMarketAnalyses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)));
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('등록된 시황 분석이 없습니다',
                        style: GoogleFonts.inter(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.38))));
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: GoogleFonts.inter(
                                      color:
                                          Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(a.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.38),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF10B981), size: 18),
                          onPressed: () => _openWrite(a),
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
}

// ─── 알림 발송 탭 ───────────────────────────────────────────────────────────

class _PushNotificationTab extends StatefulWidget {
  const _PushNotificationTab();

  @override
  State<_PushNotificationTab> createState() => _PushNotificationTabState();
}

class _PushNotificationTabState extends State<_PushNotificationTab> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _sending = false;
  String? _lastResult;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    setState(() {
      _sending = true;
      _lastResult = null;
    });

    try {
      // FcmDirectService로 직접 발송 (Cloud Function 의존 없음)
      await FcmDirectService.sendTopicNotification(title: title, body: body);
      _titleController.clear();
      _bodyController.clear();
      setState(() => _lastResult = '✅ 발송 완료! 전체 유저에게 전송됩니다.');
    } catch (e) {
      setState(() => _lastResult = '❌ 오류: $e');
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '전체 유저에게 푸시 알림을 보냅니다',
            style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 24),
          Text('제목', style: GoogleFonts.inter(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: '예) 📈 새 추천주 등록!',
              hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Text('내용', style: GoogleFonts.inter(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyController,
            style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '예) 지금 바로 확인해보세요!',
              hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: const Color(0xFF10B981).withValues(alpha: 0.4),
              ),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _sending ? '발송 중...' : '전체 발송',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: Text(_lastResult!, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 유저 목록 탭 ────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getAdminUserList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}', style: GoogleFonts.inter(color: cs.onSurface)));
        }
        final users = snapshot.data ?? [];
        final today = DateTime.now();
        final todayCount = users.where((u) {
          final ts = u['createdAt'] as Timestamp?;
          if (ts == null) return false;
          final d = ts.toDate();
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }).length;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text('전체 가입자', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('${users.length}명', style: GoogleFonts.inter(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 22)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: cs.onSurface.withValues(alpha: 0.1)),
                    Expanded(
                      child: Column(
                        children: [
                          Text('오늘 가입', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('+$todayCount명', style: GoogleFonts.inter(color: const Color(0xFF10B981), fontWeight: FontWeight.w700, fontSize: 22)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final u = users[i - 1];
            final uid = u['uid'] as String;
            final nickname = u['nickname'] as String;
            final commentCount = u['commentCount'] as int;
            final createdAt = u['createdAt'] as Timestamp?;
            final joinDate = createdAt != null
                ? DateFormat('yyyy.MM.dd').format(createdAt.toDate())
                : '-';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname.isNotEmpty ? nickname : '(닉네임 없음)',
                          style: GoogleFonts.inter(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          uid,
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '댓글 $commentCount',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF10B981),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '가입 $joinDate',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── 신고 관리 탭 ──────────────────────────────────────────────────────────────

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reports = await _firestoreService.getReports();
    if (mounted) setState(() { _reports = reports; _loading = false; });
  }

  Future<void> _delete(String reportId) async {
    await _firestoreService.deleteReport(reportId);
    if (mounted) setState(() => _reports.removeWhere((r) => r['id'] == reportId));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
    if (_reports.isEmpty) {
      return Center(child: Text('신고 내역이 없습니다', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF10B981),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        separatorBuilder: (_, i) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = _reports[i];
          final createdAt = (r['createdAt'] as Timestamp?)?.toDate();
          final typeLabel = switch (r['contentType'] as String? ?? '') {
            'post' => '자유게시판',
            'journal' => '매매일지',
            'comment' => '댓글',
            _ => '기타',
          };
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeLabel, style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text(r['reason'] as String? ?? '', style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => _delete(r['id'] as String),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 6),
              Text('신고자: ${r['reporterUid']}', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 11)),
              Text('대상: ${r['targetUid']}', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 11)),
              Text('컨텐츠 ID: ${r['contentId']}', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 11)),
              if (createdAt != null)
                Text(DateFormat('yyyy.MM.dd HH:mm').format(createdAt),
                    style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
            ]),
          );
        },
      ),
    );
  }
}


