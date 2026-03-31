import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/market_analysis.dart';
import '../services/deep_link_service.dart';

class MarketAnalysisDetailScreen extends StatelessWidget {
  final MarketAnalysis analysis;

  const MarketAnalysisDetailScreen({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('시황 분석',
            style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined,
                size: 20, color: cs.onSurface.withValues(alpha: 0.6)),
            onPressed: () => Share.share(
              '📊 주식저장소 시황 분석\n'
              '━━━━━━━━━━━━━━━━━━\n'
              '${analysis.title}\n\n'
              '${analysis.body.length > 100 ? '${analysis.body.substring(0, 100)}...' : analysis.body}\n'
              '━━━━━━━━━━━━━━━━━━\n'
              '👉 ${DeepLinkService.analysisUrl(analysis)}',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜
            Text(
              DateFormat('yyyy년 MM월 dd일').format(analysis.createdAt),
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.38), fontSize: 12),
            ),
            const SizedBox(height: 10),
            // 제목
            Text(
              analysis.title,
              style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.35),
            ),
            const SizedBox(height: 6),
            Divider(
                height: 28,
                thickness: 0.5,
                color: cs.onSurface.withValues(alpha: 0.1)),
            // 본문 (마크다운 렌더링)
            MarkdownBody(
              data: analysis.body,
              sizedImageBuilder: (config) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: config.uri.toString(),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      height: 200,
                      color: cs.onSurface.withValues(alpha: 0.05),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF4ADE80), strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, _, _) => const SizedBox(),
                  ),
                ),
              ),
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 15,
                    height: 1.9),
                strong: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.9),
                em: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    height: 1.9),
                del: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 15,
                    decoration: TextDecoration.lineThrough,
                    height: 1.9),
                listBullet: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontSize: 15,
                    height: 1.9),
              ),
              shrinkWrap: true,
              softLineBreak: true,
            ),
            // 이미지
            if (analysis.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 24),
              ...analysis.imageUrls.map(
                (url) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        height: 200,
                        color: cs.onSurface.withValues(alpha: 0.05),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF4ADE80), strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        height: 120,
                        color: cs.onSurface.withValues(alpha: 0.05),
                        child: Icon(Icons.broken_image_outlined,
                            color: cs.onSurface.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
