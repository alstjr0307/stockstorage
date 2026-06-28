import 'package:flutter/material.dart';

import '../models/market_calendar_event.dart';
import '../services/firestore_service.dart';

/// 경제·실적·IPO 캘린더 전체 화면.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirestoreService();
  late final TabController _tabController;
  // build() 안에서 만들면 setState마다 새 구독이 생겨 깜빡임/재로딩됨 → 한 번만 생성.
  late final Stream<List<MarketCalendarEvent>> _stream;

  static const _filters = <CalendarEventType?>[
    null, // 전체
    CalendarEventType.earnings,
    CalendarEventType.economic,
    CalendarEventType.ipo,
  ];

  @override
  void initState() {
    super.initState();
    _stream = _firestore.watchMarketCalendar();
    _tabController = TabController(length: _filters.length, vsync: this);
    _tabController.addListener(() {
      // 탭 전환 1회당 setState 1회만 (애니메이션 중 중복 호출 방지)
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '📅 경제 캘린더',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: onSurface.withValues(alpha: 0.5),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: '전체'),
            Tab(text: '실적'),
            Tab(text: '지표'),
            Tab(text: 'IPO'),
          ],
        ),
      ),
      body: StreamBuilder<List<MarketCalendarEvent>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? const [];
          final filter = _filters[_tabController.index];
          final events = filter == null
              ? all
              : all.where((e) => e.type == filter).toList();

          if (events.isEmpty) {
            return _EmptyState(hasAny: all.isNotEmpty);
          }
          return _CalendarList(events: events);
        },
      ),
    );
  }
}

/// 날짜별로 그룹핑한 리스트.
class _CalendarList extends StatelessWidget {
  const _CalendarList({required this.events});

  final List<MarketCalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    // 날짜(yyyy-MM-dd) → 이벤트
    final groups = <String, List<MarketCalendarEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final dates = groups.keys.toList()..sort();

    final items = <Widget>[];
    for (final date in dates) {
      items.add(_DateHeader(date: date));
      for (final e in groups[date]!) {
        items.add(_EventTile(event: e));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: items,
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final parsed = DateTime.tryParse(date);
    final label = parsed != null ? _formatDate(parsed) : date;
    final isToday = parsed != null && _isSameDay(parsed, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${d.month}월 ${d.day}일 (${weekdays[d.weekday - 1]})';
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final MarketCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final meta = _typeMeta(event.type);
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(meta.icon, color: meta.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Badge(text: meta.label, color: meta.color),
                    if (event.importance >= 3) ...[
                      const SizedBox(width: 6),
                      const _Badge(text: '🔥 중요', color: Color(0xFFEF4444)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_subtitle(event) != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(event)!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 12.5,
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

  String? _subtitle(MarketCalendarEvent e) {
    switch (e.type) {
      case CalendarEventType.earnings:
        final hour = e.extra['hour'] as String?;
        final eps = e.extra['epsEstimate'];
        final parts = <String>[];
        if (hour != null) parts.add(hour);
        if (eps != null) parts.add('EPS 예상 \$$eps');
        return parts.isEmpty ? '미국 증시' : parts.join(' · ');
      case CalendarEventType.economic:
        return '미국 경제지표';
      case CalendarEventType.ipo:
        final exch = e.extra['exchange'] as String?;
        final price = e.extra['priceRange'];
        final parts = <String>[];
        if (exch != null) parts.add(exch);
        if (price != null) parts.add('공모가 \$$price');
        return parts.isEmpty ? '신규 상장' : parts.join(' · ');
      case CalendarEventType.unknown:
        return null;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAny});

  /// 전체 데이터는 있는데 해당 탭만 비었는지 여부
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded,
                size: 56, color: onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              hasAny ? '이 분류의 예정 일정이 없어요' : '예정된 일정이 없어요',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '실적·경제지표·IPO 일정이 곧 업데이트됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeMeta {
  const _TypeMeta(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_TypeMeta _typeMeta(CalendarEventType type) {
  switch (type) {
    case CalendarEventType.earnings:
      return const _TypeMeta('실적', Icons.bar_chart_rounded, Color(0xFF10B981));
    case CalendarEventType.economic:
      return const _TypeMeta(
          '지표', Icons.account_balance_rounded, Color(0xFF3B82F6));
    case CalendarEventType.ipo:
      return const _TypeMeta('IPO', Icons.rocket_launch_rounded, Color(0xFFF59E0B));
    case CalendarEventType.unknown:
      return const _TypeMeta('기타', Icons.event_rounded, Color(0xFF94A3B8));
  }
}
