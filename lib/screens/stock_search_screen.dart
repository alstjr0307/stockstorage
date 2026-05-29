import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/stock_price_service.dart';
import 'stock_detail_screen.dart';

class StockSearchScreen extends StatefulWidget {
  const StockSearchScreen({
    super.key,
    this.title = '종목 검색',
    this.subtitle,
    this.onPick,
  });

  /// 화면 상단 큰 제목.
  final String title;

  /// 제목 아래 보조 안내.
  final String? subtitle;

  /// 비어있으면 종목 상세로 이동 (기본 동작).
  /// 지정하면 결과를 콜백으로 넘기고 그 외 동작은 호출 측에 위임.
  final void Function(StockSearchResult result)? onPick;

  @override
  State<StockSearchScreen> createState() => _StockSearchScreenState();
}

class _StockSearchScreenState extends State<StockSearchScreen> {
  static const _recentPrefsKey = 'stock_search_recent_v1';
  static const _maxRecent = 6;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<StockSearchResult> _results = const [];
  List<String> _recent = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // 포커스 보더 상태 갱신을 위해 빌드만 트리거
    if (mounted) setState(() {});
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recent = prefs.getStringList(_recentPrefsKey) ?? const []);
  }

  Future<void> _saveRecent(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = <String>[trimmed];
    for (final r in _recent) {
      if (r == trimmed) continue;
      updated.add(r);
      if (updated.length >= _maxRecent) break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentPrefsKey, updated);
    if (!mounted) return;
    setState(() => _recent = updated);
  }

  Future<void> _removeRecent(String query) async {
    final updated = _recent.where((r) => r != query).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentPrefsKey, updated);
    if (!mounted) return;
    setState(() => _recent = updated);
  }

  Future<void> _clearAllRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentPrefsKey);
    if (!mounted) return;
    setState(() => _recent = const []);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    final results = await StockPriceService.searchStocks(query);
    if (!mounted || _controller.text.trim() != query) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _submitQuery(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _saveRecent(query);
    _search(query);
  }

  void _useRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _focusNode.requestFocus();
    _search(query);
  }

  void _openResult(StockSearchResult result) {
    HapticFeedback.selectionClick();
    _saveRecent(result.name.isEmpty ? result.ticker : result.name);
    final onPick = widget.onPick;
    if (onPick != null) {
      onPick(result);
      return;
    }
    Navigator.push(
      context,
      stockDetailRoute(
        stockPickFromSearchResult(result),
        enablePickFeatures: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: widget.title,
              subtitle: widget.subtitle,
              isDark: isDark,
              onBack: () => Navigator.maybePop(context),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: _SearchField(
                controller: _controller,
                focusNode: _focusNode,
                loading: _loading,
                isDark: isDark,
                onChanged: _onChanged,
                onSubmitted: _submitQuery,
                onClear: () {
                  _controller.clear();
                  _onChanged('');
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                child: _buildBody(cs, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, bool isDark) {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return _IdleView(
        key: const ValueKey('idle'),
        recent: _recent,
        isDark: isDark,
        onTapRecent: _useRecent,
        onRemoveRecent: _removeRecent,
        onClearAll: _clearAllRecent,
      );
    }
    if (_loading && _results.isEmpty) {
      return _SkeletonList(key: const ValueKey('skeleton'), isDark: isDark);
    }
    if (_results.isEmpty) {
      return _NoResultsView(
        key: const ValueKey('noresult'),
        query: _lastQuery,
        isDark: isDark,
      );
    }
    return _ResultsList(
      key: const ValueKey('results'),
      results: _results,
      isDark: isDark,
      onTap: _openResult,
    );
  }
}

// ───────────────────────── 헤더 ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onBack,
  });

  final String title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurface.withValues(alpha: 0.8),
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Text(
                subtitle!,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── 검색 입력 ─────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.isDark,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focused = focusNode.hasFocus;
    final fieldBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.035);
    final borderColor = focused
        ? const Color(0xFF10B981).withValues(alpha: 0.7)
        : (isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06));

    final hasText = controller.text.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: focused ? 1.5 : 1),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: focused
                ? const Color(0xFF10B981)
                : cs.onSurface.withValues(alpha: 0.5),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              cursorColor: const Color(0xFF10B981),
              cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: '종목명 또는 티커',
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.35),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: loading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  )
                : hasText
                ? IconButton(
                    key: const ValueKey('clear'),
                    onPressed: onClear,
                    splashRadius: 18,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), width: 18, height: 18),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 초기 (검색어 없음) ─────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({
    super.key,
    required this.recent,
    required this.isDark,
    required this.onTapRecent,
    required this.onRemoveRecent,
    required this.onClearAll,
  });

  final List<String> recent;
  final bool isDark;
  final ValueChanged<String> onTapRecent;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      physics: const ClampingScrollPhysics(),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Text(
                '최근 검색',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClearAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '전체 삭제',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in recent)
                _RecentChip(
                  label: q,
                  isDark: isDark,
                  onTap: () => onTapRecent(q),
                  onRemove: () => onRemoveRecent(q),
                ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        _TipCard(isDark: isDark),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({
    required this.label,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
  });

  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isDark
        ? const Color(0xFF10B981).withValues(alpha: 0.08)
        : const Color(0xFF10B981).withValues(alpha: 0.06);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 16,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              Text(
                '검색 팁',
                style: TextStyle(
                  color: const Color(0xFF10B981),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TipLine(
            text: '한글 종목명: 삼성전자, SK하이닉스',
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 4),
          _TipLine(
            text: '국내 종목코드: 005930, 000660',
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 4),
          _TipLine(
            text: '미국 티커: TSLA, NVDA, AAPL',
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

class _TipLine extends StatelessWidget {
  const _TipLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── 결과 없음 ─────────────────────────

class _NoResultsView extends StatelessWidget {
  const _NoResultsView({
    super.key,
    required this.query,
    required this.isDark,
  });

  final String query;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 28,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '"$query" 검색 결과가 없어요',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.75),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '철자나 종목코드를 다시 확인해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 결과 리스트 ─────────────────────────

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    super.key,
    required this.results,
    required this.isDark,
    required this.onTap,
  });

  final List<StockSearchResult> results;
  final bool isDark;
  final ValueChanged<StockSearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    // 시장별로 그룹: KS/KQ는 KR로 묶고, US는 별도.
    final kr = <StockSearchResult>[];
    final us = <StockSearchResult>[];
    for (final r in results) {
      switch (r.market.toUpperCase()) {
        case 'KS':
        case 'KQ':
          kr.add(r);
          break;
        case 'US':
          us.add(r);
          break;
        default:
          us.add(r);
      }
    }

    final items = <Widget>[];
    if (kr.isNotEmpty) {
      items.add(_SectionHeader(label: '국내', count: kr.length, isDark: isDark));
      items.add(const SizedBox(height: 8));
      for (var i = 0; i < kr.length; i++) {
        items.add(
          _ResultCard(result: kr[i], isDark: isDark, onTap: () => onTap(kr[i])),
        );
        if (i != kr.length - 1) items.add(const SizedBox(height: 8));
      }
      items.add(const SizedBox(height: 18));
    }
    if (us.isNotEmpty) {
      items.add(_SectionHeader(label: '미국', count: us.length, isDark: isDark));
      items.add(const SizedBox(height: 8));
      for (var i = 0; i < us.length; i++) {
        items.add(
          _ResultCard(result: us[i], isDark: isDark, onTap: () => onTap(us[i])),
        );
        if (i != us.length - 1) items.add(const SizedBox(height: 8));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      physics: const ClampingScrollPhysics(),
      children: items,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.isDark,
  });

  final String label;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  const _ResultCard({
    required this.result,
    required this.isDark,
    required this.onTap,
  });

  final StockSearchResult result;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _pressed = false;

  Color get _marketColor => switch (widget.result.market.toUpperCase()) {
    'KS' => const Color(0xFF4D9BFF),
    'KQ' => const Color(0xFFFBBF24),
    'US' => const Color(0xFFA78BFA),
    _ => Colors.grey,
  };

  String get _marketLabel => switch (widget.result.market.toUpperCase()) {
    'KS' => 'KOSPI',
    'KQ' => 'KOSDAQ',
    'US' => 'US',
    _ => widget.result.market.toUpperCase(),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardBg = widget.isDark
        ? const Color(0xFF1A2035)
        : Colors.white;
    final borderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _marketColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    _marketLabel == 'KOSPI'
                        ? 'KS'
                        : _marketLabel == 'KOSDAQ'
                        ? 'KQ'
                        : 'US',
                    style: TextStyle(
                      color: _marketColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.result.name.isEmpty
                            ? widget.result.ticker
                            : widget.result.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            widget.result.ticker,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (widget.result.exchange.isNotEmpty &&
                              widget.result.exchange != _marketLabel) ...[
                            Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                widget.result.exchange,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 스켈레톤 ─────────────────────────

class _SkeletonList extends StatefulWidget {
  const _SkeletonList({super.key, required this.isDark});

  final bool isDark;

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(bottom: i == 4 ? 0 : 8),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            final base = widget.isDark ? 0.06 : 0.04;
            final highlight = widget.isDark ? 0.12 : 0.08;
            final alpha = base + (highlight - base) * t;
            final color = widget.isDark
                ? Colors.white.withValues(alpha: alpha)
                : Colors.black.withValues(alpha: alpha);
            return Container(
              height: 68,
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? const Color(0xFF1A2035)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 130,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: 80,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
