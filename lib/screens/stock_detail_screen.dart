import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';

class StockDetailScreen extends StatelessWidget {
  final StockPick pick;

  const StockDetailScreen({super.key, required this.pick});

  @override
  Widget build(BuildContext context) {
    final returnRate = pick.returnRate;
    final isPositive = returnRate >= 0;
    final formatter = NumberFormat('#,###');

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
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
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
                      Text(
                        DateFormat('yyyy.MM.dd HH:mm').format(pick.createdAt),
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      color: isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 가격 카드
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _priceItem('매수가', '₩${formatter.format(pick.buyPrice.toInt())}', Colors.white70),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: _priceItem('목표가', '₩${formatter.format(pick.targetPrice.toInt())}', const Color(0xFF4ADE80)),
                  ),
                  if (pick.currentPrice != null) ...[
                    Container(width: 1, height: 40, color: Colors.white12),
                    Expanded(
                      child: _priceItem('현재가', '₩${formatter.format(pick.currentPrice!.toInt())}', Colors.blueAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 카테고리
            _sectionLabel('투자 기간'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                pick.category,
                style: GoogleFonts.inter(color: Colors.white70),
              ),
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
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
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
        letterSpacing: 0.5,
      ),
    );
  }
}
