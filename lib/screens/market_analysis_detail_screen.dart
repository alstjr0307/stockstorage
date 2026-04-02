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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final coverImage = analysis.imageUrls.isNotEmpty ? analysis.imageUrls.first : null;
    final extraImages =
        analysis.imageUrls.length > 1 ? analysis.imageUrls.skip(1).toList() : const <String>[];
    final renderedBody = _normalizeBodyForMarkdown(analysis.body);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
          child: _TopActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          '시황 분석',
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 6, bottom: 6),
            child: _TopActionButton(
              icon: Icons.share_outlined,
              onTap: () => Share.share(_shareText()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroHeader(
                    analysis: analysis,
                    coverImage: coverImage,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarkdownBody(
                            data: renderedBody,
                            selectable: true,
                            softLineBreak: true,
                            shrinkWrap: true,
                            sizedImageBuilder: (config) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: _InlineImage(url: config.uri.toString()),
                            ),
                            styleSheet: _markdownStyleSheet(context),
                          ),
                          if (extraImages.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            ...extraImages.map(
                              (url) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _InlineImage(url: url),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _shareText() {
    final preview = analysis.body.replaceAll('\n', ' ').trim();
    final shortPreview =
        preview.length > 100 ? '${preview.substring(0, 100)}...' : preview;
    return '주식저장소 시황 분석\n\n'
        '${analysis.title}\n\n'
        '$shortPreview\n\n'
        '${DeepLinkService.analysisUrl(analysis)}';
  }

  String _normalizeBodyForMarkdown(String body) {
    return body.replaceAllMapped(
      RegExp(r'(^|\n)(\d+)\.\s', multiLine: true),
      (match) => '${match.group(1)}${match.group(2)}\\. ',
    );
  }

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    TextStyle body(double size, double height, {FontWeight weight = FontWeight.w500}) {
      return GoogleFonts.inter(
        color: cs.onSurface.withValues(alpha: 0.88),
        fontSize: size,
        height: height,
        fontWeight: weight,
      );
    }

    return MarkdownStyleSheet(
      p: body(16, 1.95),
      pPadding: const EdgeInsets.only(bottom: 14),
      strong: body(16, 1.95, weight: FontWeight.w800).copyWith(color: cs.onSurface),
      em: body(16, 1.95).copyWith(fontStyle: FontStyle.italic),
      del: body(16, 1.95).copyWith(
        color: cs.onSurface.withValues(alpha: 0.5),
        decoration: TextDecoration.lineThrough,
      ),
      blockquote: body(15, 1.8).copyWith(
        color: cs.onSurface.withValues(alpha: 0.72),
      ),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0xFF4ADE80).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.16)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      h1: body(26, 1.4, weight: FontWeight.w800).copyWith(color: cs.onSurface),
      h2: body(22, 1.45, weight: FontWeight.w800).copyWith(color: cs.onSurface),
      h3: body(19, 1.5, weight: FontWeight.w700).copyWith(color: cs.onSurface),
      h1Padding: const EdgeInsets.only(top: 10, bottom: 12),
      h2Padding: const EdgeInsets.only(top: 8, bottom: 10),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 8),
      code: GoogleFonts.jetBrainsMono(
        color: cs.onSurface,
        fontSize: 13.5,
        height: 1.7,
        fontWeight: FontWeight.w500,
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      listBullet: body(16, 1.95),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final MarketAnalysis analysis;
  final String? coverImage;
  final bool isDark;

  const _HeroHeader({
    required this.analysis,
    required this.coverImage,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = const Color(0xFF4ADE80);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF182235), Color(0xFF0D1423)]
              : const [Color(0xFFE8FFF0), Color(0xFFF8FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: isDark ? 0.18 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverImage != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: coverImage!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => _imagePlaceholder(context, height: double.infinity),
                  errorWidget: (_, _, _) => _imageError(context),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: DateFormat('yyyy년 MM월 dd일').format(analysis.createdAt),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  analysis.title,
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 54,
                  height: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFF4ADE80).withValues(alpha: 0.14)
            : cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? const Color(0xFF4ADE80).withValues(alpha: 0.26)
              : cs.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: accent ? const Color(0xFF1F9D55) : cs.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 19,
          color: cs.onSurface.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _InlineImage extends StatelessWidget {
  final String url;

  const _InlineImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CachedNetworkImage(
        imageUrl: url,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, _) => _imagePlaceholder(context),
        errorWidget: (_, _, _) => _imageError(context),
      ),
    );
  }
}

Widget _imagePlaceholder(BuildContext context, {double height = 220}) {
  final cs = Theme.of(context).colorScheme;

  return Container(
    height: height,
    color: cs.onSurface.withValues(alpha: 0.05),
    child: const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF4ADE80),
        strokeWidth: 2,
      ),
    ),
  );
}

Widget _imageError(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return Container(
    height: 160,
    color: cs.onSurface.withValues(alpha: 0.05),
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: cs.onSurface.withValues(alpha: 0.28),
      ),
    ),
  );
}
