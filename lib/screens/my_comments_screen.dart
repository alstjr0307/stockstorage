import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import 'stock_detail_screen.dart';

class MyCommentsScreen extends StatefulWidget {
  final String uid;
  const MyCommentsScreen({super.key, required this.uid});

  @override
  State<MyCommentsScreen> createState() => _MyCommentsScreenState();
}

class _MyCommentsScreenState extends State<MyCommentsScreen> {
  final _fs = FirestoreService();
  late Future<List<({StockPick? pick, String text, DateTime createdAt})>>
  _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<({StockPick? pick, String text, DateTime createdAt})>>
  _load() async {
    final comments = await _fs.getMyComments(widget.uid);
    final pickCache = <String, StockPick?>{};
    for (final c in comments) {
      if (!pickCache.containsKey(c.pickId)) {
        pickCache[c.pickId] = await _fs.getStockPickOnce(c.pickId);
      }
    }
    return comments
        .map(
          (c) =>
              (pick: pickCache[c.pickId], text: c.text, createdAt: c.createdAt),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '내 댓글',
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4ADE80),
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                '불러오기 실패',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: cs.onSurface.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '작성한 댓글이 없습니다',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.35),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = items[i];
              final pick = item.pick;
              return GestureDetector(
                onTap: pick == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StockDetailScreen(pick: pick),
                        ),
                      ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A2035) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pick != null
                                  ? '${pick.name}  ${pick.ticker}'
                                  : '삭제된 종목',
                              style: GoogleFonts.inter(
                                color: pick != null
                                    ? const Color(0xFF4ADE80)
                                    : cs.onSurface.withValues(alpha: 0.35),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            DateFormat('MM/dd HH:mm').format(item.createdAt),
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.35),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.text,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
