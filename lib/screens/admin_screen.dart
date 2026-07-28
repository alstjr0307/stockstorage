import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/announcement.dart';
import '../models/market_analysis.dart';
import '../models/post.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../utils/bot_profiles.dart';
import '../widgets/stock_search_field.dart';
import 'write_market_analysis_screen.dart';

/// 관리자 패널. [embedded] 는 웹 셸 안에 탭으로 붙일 때 뒤로가기 버튼을 숨긴다.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
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
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          '관리자 패널',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.38),
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: TextStyle(fontSize: 14),
          isScrollable: true,
          tabs: const [
            Tab(text: '종목 등록'),
            Tab(text: '목록 관리'),
            Tab(text: '공지사항'),
            Tab(text: '봇글 작성'),
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
          _BotPostTab(),
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
    _buyPriceController = TextEditingController(
      text: p != null ? p.buyPrice.toInt().toString() : '',
    );
    _targetPriceController = TextEditingController(
      text: p != null ? p.targetPrice.toInt().toString() : '',
    );
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
          _buildField(
            '매수가',
            _buyPriceController,
            hint: '70000',
            isNumber: true,
          ),
          const SizedBox(height: 14),
          _buildField(
            '목표가',
            _targetPriceController,
            hint: '85000',
            isNumber: true,
          ),
          const SizedBox(height: 14),
          _buildField(
            '매수 근거',
            _reasonController,
            hint: '매수 근거를 입력하세요...',
            maxLines: 5,
          ),
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
              title: Text(
                '로그인 후 열람 가능',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              subtitle: Text(
                '로그인 사용자만 상세 열람 가능',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
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
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(
                      _isEdit ? '수정하기' : '등록하기',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
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
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.54),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: isNumber
              ? TextInputType.number
              : TextInputType.multiline,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.24)),
            filled: true,
            fillColor: const Color(0xFF1A2035),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF10B981),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
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
        Text(
          '실적 발표일',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.54),
            fontSize: 12,
          ),
        ),
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
                Icon(
                  Icons.calendar_today,
                  color: cs.onSurface.withValues(alpha: 0.38),
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _earningsDate != null
                        ? DateFormat('yyyy년 MM월 dd일').format(_earningsDate!)
                        : '선택사항',
                    style: TextStyle(
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
                    child: Icon(
                      Icons.close,
                      color: cs.onSurface.withValues(alpha: 0.38),
                      size: 16,
                    ),
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
        buyPrice: double.parse(_buyPriceController.text.replaceAll(',', '')),
        targetPrice: double.parse(
          _targetPriceController.text.replaceAll(',', ''),
        ),
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
        _firestoreService
            .sendPushNotification(
              title: '📈 새 추천 종목',
              body: '새 추천 종목이 등록되었습니다. 지금 확인해보세요!',
              topic: 'new_pick_alerts',
            )
            .catchError((_) {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pick.name} ${_isEdit ? '수정' : '등록'} 완료!',
              style: TextStyle(),
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
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.redAccent),
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
                child: CircularProgressIndicator(color: Color(0xFF10B981)),
              );
            }

            final activePicks = activeSnap.data ?? [];
            final completedPicks = completedSnap.data ?? [];

            if (activePicks.isEmpty && completedPicks.isEmpty) {
              return Center(
                child: Text(
                  '등록된 종목이 없습니다',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.38)),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (activePicks.isNotEmpty) ...[
                  _sectionLabel(cs, '진행 중 (${activePicks.length})'),
                  const SizedBox(height: 8),
                  ...activePicks.map(
                    (pick) => _ManageCard(
                      pick: pick,
                      firestoreService: firestoreService,
                    ),
                  ),
                ],
                if (completedPicks.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionLabel(cs, '종료 종목 (${completedPicks.length})'),
                  const SizedBox(height: 8),
                  ...completedPicks.map(
                    (pick) => _ManageCard(
                      pick: pick,
                      firestoreService: firestoreService,
                    ),
                  ),
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
      style: TextStyle(
        color: cs.onSurface.withValues(alpha: 0.45),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (pick.isPremium) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.star,
                        color: Color(0xFFFFD700),
                        size: 13,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pick.name,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                  ),
                ),
                Text(
                  '매수 ${pick.buyPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원  →  목표 ${pick.targetPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // 종료 버튼 (active 상태일 때만)
          if (!pick.isCompleted)
            IconButton(
              icon: const Icon(
                Icons.check_circle_outline,
                color: Colors.orangeAccent,
                size: 20,
              ),
              tooltip: '종료 처리',
              onPressed: () => _confirmClose(context),
            ),
          // 편집 버튼 (진행 중만)
          if (!pick.isCompleted)
            IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                color: Color(0xFF10B981),
                size: 20,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _EditScreen(pick: pick)),
              ),
            ),
          // 삭제 버튼
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.redAccent,
              size: 20,
            ),
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
        title: Text(
          '종료 처리',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${pick.name} (${pick.ticker})\n실제 종료가를 입력하세요.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: '종료가',
                hintStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.24),
                ),
                filled: true,
                fillColor: const Color(0xFF0A0E1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final price = double.tryParse(
                controller.text.replaceAll(',', ''),
              );
              Navigator.pop(context, price);
            },
            child: Text(
              '종료',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (closedPrice != null) {
      try {
        await firestoreService.closeStockPick(pick.id, closedPrice);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${pick.name} 종료 처리됨', style: TextStyle()),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: Text(
          '삭제 확인',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '${pick.name}(${pick.ticker})을 삭제하시겠습니까?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '삭제',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              content: Text('${pick.name} 삭제됨', style: TextStyle()),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류: $e'),
              backgroundColor: Colors.redAccent,
            ),
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
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).colorScheme.onSurface,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '종목 수정',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _editing != null ? '공지 수정 완료' : '공지 등록 완료',
              style: TextStyle(),
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        _cancelEdit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.redAccent),
        );
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
        title: Text(
          '삭제 확인',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '공지 "${a.title}"를 삭제하시겠습니까?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '삭제',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
            border: Border(
              bottom: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing != null ? '공지 수정' : '공지 등록',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: _inputDeco(context, '제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
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
                  Text(
                    '상단 고정',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  if (_editing != null)
                    TextButton(
                      onPressed: _cancelEdit,
                      child: Text(
                        '취소',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            _editing != null ? '수정' : '등록',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    '등록된 공지가 없습니다',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                );
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
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (a.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.push_pin,
                              color: Color(0xFF10B981),
                              size: 14,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.title,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                a.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.38),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                          onPressed: () => _startEdit(a),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 18,
                          ),
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
      hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.24)),
      filled: true,
      fillColor: const Color(0xFF0A0E1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ─── 봇글 작성 탭 ───────────────────────────────────────────────────────────

class _BotPostTab extends StatefulWidget {
  const _BotPostTab();

  @override
  State<_BotPostTab> createState() => _BotPostTabState();
}

class _BotPostTabState extends State<_BotPostTab> {
  final _fs = FirestoreService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty || _saving) return;

    final rng = DateTime.now().millisecondsSinceEpoch;
    final profile = botProfiles[rng % botProfiles.length];
    final fakeUid = generateFakeBotUid();

    setState(() => _saving = true);
    try {
      await _fs.createBotPost(
        Post(
          id: '',
          uid: fakeUid,
          nickname: profile.nickname,
          title: title,
          content: body,
          likes: 0,
          createdAt: DateTime.now(),
          imageUrls: const [],
          authorLevel: profile.level,
        ),
        level: profile.level,
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${profile.nickname} Lv.${profile.level} 이름으로 글을 등록했습니다.',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('글 등록 실패: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '봇글 작성',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '닉네임과 레벨은 등록할 때마다 봇계정 프로필로 자동 지정됩니다.',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                style: TextStyle(color: cs.onSurface),
                textInputAction: TextInputAction.next,
                decoration: _inputDeco(context, '글 제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                minLines: 8,
                maxLines: 14,
                style: TextStyle(color: cs.onSurface, height: 1.45),
                decoration: _inputDeco(context, '글 내용'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF07120E),
                    disabledBackgroundColor: const Color(
                      0xFF10B981,
                    ).withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF07120E),
                          ),
                        )
                      : const Text(
                          '봇글 등록',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(BuildContext context, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.24)),
      filled: true,
      fillColor: const Color(0xFF0A0E1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        title: Text(
          '삭제 확인',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '"${a.title}"를 삭제하시겠습니까?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '삭제',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _openWrite(),
              icon: const Icon(Icons.add, size: 20),
              label: Text(
                '새 시황 분석 작성',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
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
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    '등록된 시황 분석이 없습니다',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                );
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.title,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                a.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.38),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                          onPressed: () => _openWrite(a),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 18,
                          ),
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
  final _firestoreService = FirestoreService();
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
      await _firestoreService.sendPushNotification(
        title: title,
        body: body,
        topic: 'new_pick_alerts',
      );
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
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '제목',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: '예) 📈 새 추천주 등록!',
              hintStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '내용',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyController,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '예) 지금 바로 확인해보세요!',
              hintStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: const Color(
                  0xFF10B981,
                ).withValues(alpha: 0.4),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _sending ? '발송 중...' : '전체 발송',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _lastResult!,
                style: TextStyle(color: cs.onSurface, fontSize: 13),
              ),
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
  final _firestoreService = FirestoreService();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _users = [];
  final List<Map<String, dynamic>> _searchResults = [];
  DocumentSnapshot? _lastDoc;
  Timer? _searchDebounce;
  bool _loading = false;
  bool _initialLoading = true;
  bool _hasMore = true;
  bool _searchLoading = false;
  String? _error;
  String _query = '';
  int _searchRequestId = 0;
  int _totalUsers = 0;
  int _todayUsers = 0;

  static const _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadMore();
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await _firestoreService.getAdminUserListSummary();
      if (!mounted) return;
      setState(() {
        _totalUsers = summary.totalUsers;
        _todayUsers = summary.todayUsers;
      });
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_query.trim().isNotEmpty || _loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _firestoreService.getAdminUserListPaged(
        startAfter: _lastDoc,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    _searchDebounce?.cancel();
    _searchRequestId++;
    setState(() {
      _users.clear();
      _searchResults.clear();
      _lastDoc = null;
      _hasMore = true;
      _initialLoading = true;
      _searchLoading = false;
      _error = null;
      _query = '';
    });
    _searchController.clear();
    await _loadSummary();
    await _loadMore();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = value;
      _searchResults.clear();
      _searchLoading = query.isNotEmpty;
      _error = null;
    });

    if (query.isEmpty) {
      _searchRequestId++;
      setState(() => _searchLoading = false);
      return;
    }

    final requestId = ++_searchRequestId;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await _firestoreService.searchAdminUsers(query);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults
            ..clear()
            ..addAll(results);
          _searchLoading = false;
        });
      } catch (e) {
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchLoading = false;
          _error = '$e';
        });
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _searchController.clear();
    setState(() {
      _query = '';
      _searchResults.clear();
      _searchLoading = false;
      _error = null;
    });
  }

  void _openUserDetail(Map<String, dynamic> user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminUserDetailScreen(
          uid: user['uid'] as String,
          initialUser: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final isSearching = q.isNotEmpty;
    final visibleUsers = isSearching ? _searchResults : _users;
    final showEmptySearch =
        isSearching && !_searchLoading && _searchResults.isEmpty;
    if (_initialLoading && _users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      );
    }
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Text('오류: $_error', style: TextStyle(color: cs.onSurface)),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF10B981),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount:
            visibleUsers.length +
            2 +
            (showEmptySearch ? 1 : 0) +
            (_searchLoading ? 1 : 0) +
            (!isSearching && (_loading || _hasMore) ? 1 : 0),
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
                        Text(
                          '전체 가입자',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_totalUsers명',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: cs.onSurface.withValues(alpha: 0.1),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '오늘 가입',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+$_todayUsers명',
                          style: TextStyle(
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          if (i == 1) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '닉네임 또는 UID 검색',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _clearSearch,
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            );
          }

          if (_searchLoading && i == 2) {
            return const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF10B981),
                  strokeWidth: 2,
                ),
              ),
            );
          }

          if (showEmptySearch && i == 2) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Center(
                child: Text(
                  '검색 결과가 없습니다',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }

          final index =
              i - 2 - (showEmptySearch ? 1 : 0) - (_searchLoading ? 1 : 0);
          if (index >= visibleUsers.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator(
                        color: Color(0xFF10B981),
                        strokeWidth: 2,
                      )
                    : Text(
                        '아래로 스크롤하면 다음 100명을 불러옵니다',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
              ),
            );
          }

          final u = visibleUsers[index];
          final uid = u['uid'] as String;
          final nickname = u['nickname'] as String;
          final level = (u['level'] as num?)?.toInt() ?? 1;
          final postCount = (u['postCount'] as num?)?.toInt() ?? 0;
          final commentCount = (u['commentCount'] as num?)?.toInt() ?? 0;
          final createdAt = u['createdAt'] as Timestamp?;
          final lastActiveAt = u['lastActiveAt'] as Timestamp?;
          final joinDate = createdAt != null
              ? DateFormat('yyyy.MM.dd').format(createdAt.toDate())
              : '-';
          final lastActiveText = lastActiveAt != null
              ? DateFormat('yyyy.MM.dd HH:mm').format(lastActiveAt.toDate())
              : '-';
          return GestureDetector(
            onTap: () => _openUserDetail(u),
            child: Container(
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
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          uid,
                          style: TextStyle(
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
                        'Lv.$level · 글/일지 $postCount · 댓글 $commentCount',
                        style: TextStyle(
                          color: const Color(0xFF10B981),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '가입 $joinDate',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '최근 접속 $lastActiveText',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── 신고 관리 탭 ──────────────────────────────────────────────────────────────

class _AdminUserDetailScreen extends StatefulWidget {
  const _AdminUserDetailScreen({required this.uid, required this.initialUser});

  final String uid;
  final Map<String, dynamic> initialUser;

  @override
  State<_AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<_AdminUserDetailScreen> {
  final _firestoreService = FirestoreService();
  late Future<Map<String, dynamic>?> _userFuture;
  late Future<({int postCount, int journalCount, int reportCount})>
  _activityFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = _firestoreService.getAdminUserDetail(widget.uid);
    _activityFuture = _firestoreService.getAdminUserActivitySummary(widget.uid);
  }

  String _formatTimestamp(dynamic value, {bool withTime = true}) {
    if (value is! Timestamp) return '-';
    final pattern = withTime ? 'yyyy.MM.dd HH:mm' : 'yyyy.MM.dd';
    return DateFormat(pattern).format(value.toDate());
  }

  String _valueText(dynamic value) {
    if (value == null) return '-';
    if (value is Timestamp) return _formatTimestamp(value);
    if (value is Map) return value.isEmpty ? '-' : value.toString();
    if (value is List) return value.isEmpty ? '-' : value.join(', ');
    final text = value.toString();
    return text.isEmpty ? '-' : text;
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.48),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF10B981),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          '유저 상세',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _userFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                '불러오기 실패: ${snap.error}',
                style: TextStyle(color: cs.onSurface),
              ),
            );
          }
          final user = snap.data ?? widget.initialUser;
          final nickname = _valueText(user['nickname']);
          final level = ((user['level'] as num?)?.toInt() ?? 1).toString();
          final uid = user['uid'] as String? ?? widget.uid;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section(
                context,
                title: '기본 정보',
                children: [
                  _row(context, '닉네임', nickname),
                  _row(context, 'UID', uid),
                  _row(context, '레벨', 'Lv.$level'),
                  _row(context, '가입일', _formatTimestamp(user['createdAt'])),
                  _row(
                    context,
                    '최근 접속',
                    _formatTimestamp(user['lastActiveAt']),
                  ),
                ],
              ),
              _section(
                context,
                title: '활동 지표',
                children: [
                  Row(
                    children: [
                      _stat(context, '글', _valueText(user['postCount'])),
                      const SizedBox(width: 8),
                      _stat(context, '댓글', _valueText(user['commentCount'])),
                      const SizedBox(width: 8),
                      _stat(context, '출석', _valueText(user['attendanceCount'])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stat(context, '보너스 XP', _valueText(user['bonusXp'])),
                      const SizedBox(width: 8),
                      FutureBuilder<
                        ({int postCount, int journalCount, int reportCount})
                      >(
                        future: _activityFuture,
                        builder: (context, activitySnap) => _stat(
                          context,
                          '일지',
                          activitySnap.hasData
                              ? '${activitySnap.data!.journalCount}'
                              : '-',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FutureBuilder<
                        ({int postCount, int journalCount, int reportCount})
                      >(
                        future: _activityFuture,
                        builder: (context, activitySnap) => _stat(
                          context,
                          '신고',
                          activitySnap.hasData
                              ? '${activitySnap.data!.reportCount}'
                              : '-',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _section(
                context,
                title: '상태 및 설정',
                children: [
                  _row(
                    context,
                    '마지막 출석',
                    _valueText(user['lastAttendanceDate']),
                  ),
                  _row(
                    context,
                    '리워드 광고일',
                    _valueText(user['lastRewardAdDate']),
                  ),
                  _row(
                    context,
                    '오늘 광고 수',
                    _valueText(user['rewardAdCountToday']),
                  ),
                  _row(
                    context,
                    '알림 설정',
                    _valueText(user['notificationSettings']),
                  ),
                  _row(context, 'FCM 토큰', _valueText(user['fcmToken'])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

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
    if (mounted) {
      setState(() {
        _reports = reports;
        _loading = false;
      });
    }
  }

  Future<void> _delete(String reportId) async {
    await _firestoreService.deleteReport(reportId);
    if (mounted) {
      setState(() => _reports.removeWhere((r) => r['id'] == reportId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      );
    }
    if (_reports.isEmpty) {
      return Center(
        child: Text(
          '신고 내역이 없습니다',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
        ),
      );
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r['reason'] as String? ?? '',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _delete(r['id'] as String),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '신고자: ${r['reporterUid']}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '대상: ${r['targetUid']}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '컨텐츠 ID: ${r['contentId']}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                if (createdAt != null)
                  Text(
                    DateFormat('yyyy.MM.dd HH:mm').format(createdAt),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
