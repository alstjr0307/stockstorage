import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import 'stock_detail_screen.dart';

class EarningsCalendarScreen extends StatefulWidget {
  const EarningsCalendarScreen({super.key});

  @override
  State<EarningsCalendarScreen> createState() => _EarningsCalendarScreenState();
}

class _EarningsCalendarScreenState extends State<EarningsCalendarScreen> {
  final _now = DateTime.now();
  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  late final Stream<List<StockPick>> _stream;

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(_now.year, _now.month);
    _stream = FirestoreService().getPicksWithEarnings();
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
          icon: Icon(Icons.arrow_back_ios,
              color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '실적 발표 캘린더',
          style: GoogleFonts.inter(
              color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<List<StockPick>>(
        stream: _stream,
        builder: (context, snapshot) {
          final picks = snapshot.data ?? [];

          // group by date key
          final Map<String, List<StockPick>> byDay = {};
          for (final p in picks) {
            if (p.earningsDate != null) {
              final key = _dayKey(p.earningsDate!);
              byDay.putIfAbsent(key, () => []).add(p);
            }
          }

          final selectedPicks = _selectedDay != null
              ? (byDay[_dayKey(_selectedDay!)] ?? [])
              : <StockPick>[];

          return Column(
            children: [
              _buildCalendar(context, cs, byDay),
              const Divider(height: 1),
              Expanded(
                child: _selectedDay == null
                    ? Center(
                        child: Text(
                          '날짜를 선택하면 실적 종목이 표시됩니다',
                          style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.38),
                              fontSize: 13),
                        ),
                      )
                    : selectedPicks.isEmpty
                        ? Center(
                            child: Text(
                              '이 날 실적 발표 종목이 없습니다',
                              style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.38),
                                  fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: selectedPicks.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) =>
                                _buildPickTile(context, selectedPicks[i]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCalendar(
    BuildContext context,
    ColorScheme cs,
    Map<String, List<StockPick>> byDay,
  ) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    // weekday: Mon=1..Sun=7 → offset so Sun=0
    final startOffset = firstDay.weekday % 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: cs.onSurface),
                onPressed: () => setState(() {
                  _focusedMonth = DateTime(
                      _focusedMonth.year, _focusedMonth.month - 1);
                  _selectedDay = null;
                }),
              ),
              Text(
                DateFormat('yyyy년 MM월').format(_focusedMonth),
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: cs.onSurface),
                onPressed: () => setState(() {
                  _focusedMonth = DateTime(
                      _focusedMonth.year, _focusedMonth.month + 1);
                  _selectedDay = null;
                }),
              ),
            ],
          ),
          // Weekday headers
          Row(
            children: ['일', '월', '화', '수', '목', '금', '토']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.38),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          // Days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: startOffset + lastDay.day,
            itemBuilder: (_, index) {
              if (index < startOffset) return const SizedBox();
              final day = index - startOffset + 1;
              final date = DateTime(
                  _focusedMonth.year, _focusedMonth.month, day);
              final key = _dayKey(date);
              final hasEarnings = byDay.containsKey(key);
              final isSelected = _selectedDay != null &&
                  _dayKey(_selectedDay!) == key;
              final isToday = _dayKey(date) == _dayKey(_now);

              return GestureDetector(
                onTap: () => setState(() => _selectedDay = date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4ADE80)
                        : isToday
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: GoogleFonts.inter(
                          color: isSelected ? Colors.black : cs.onSurface,
                          fontSize: 13,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      if (hasEarnings)
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black
                                : const Color(0xFF4ADE80),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPickTile(BuildContext context, StockPick pick) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockDetailScreen(pick: pick)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  pick.market,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF4ADE80),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pick.name,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      )),
                  Text(pick.ticker,
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.38),
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: cs.onSurface.withValues(alpha: 0.38), size: 18),
          ],
        ),
      ),
    );
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
