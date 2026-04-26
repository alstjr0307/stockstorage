import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    final coverImage = analysis.imageUrls.isNotEmpty
        ? analysis.imageUrls.first
        : null;
    final extraImages = analysis.imageUrls.length > 1
        ? analysis.imageUrls.skip(1).toList()
        : const <String>[];
    final renderedBody = _normalizeBodyForMarkdown(analysis.body);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0E1A)
          : const Color(0xFFF8F9FA),
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
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StaggerReveal(
                    delay: const Duration(milliseconds: 40),
                    child: _HeroHeader(
                      analysis: analysis,
                      coverImage: coverImage,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _StaggerReveal(
                    delay: const Duration(milliseconds: 110),
                    child: Container(
                      height: 1,
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _StaggerReveal(
                    delay: const Duration(milliseconds: 180),
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
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _InlineImage(url: url),
                            ),
                          ),
                        ],
                      ],
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
    final shortPreview = preview.length > 100
        ? '${preview.substring(0, 100)}...'
        : preview;
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

    TextStyle body(
      double size,
      double height, {
      FontWeight weight = FontWeight.w400,
    }) {
      return TextStyle(
        color: cs.onSurface.withValues(alpha: 0.88),
        fontSize: size,
        height: height,
        fontWeight: weight,
      );
    }

    return MarkdownStyleSheet(
      p: body(16, 1.65),
      pPadding: const EdgeInsets.only(bottom: 16),
      strong: body(
        16,
        1.65,
        weight: FontWeight.w700,
      ).copyWith(color: cs.onSurface),
      em: body(16, 1.65).copyWith(fontStyle: FontStyle.italic),
      del: body(16, 1.65).copyWith(
        color: cs.onSurface.withValues(alpha: 0.5),
        decoration: TextDecoration.lineThrough,
      ),
      blockquote: body(
        15,
        1.65,
      ).copyWith(color: cs.onSurface.withValues(alpha: 0.72)),
      blockquoteDecoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.15),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      h1: body(26, 1.25, weight: FontWeight.w700).copyWith(color: cs.onSurface),
      h2: body(22, 1.3, weight: FontWeight.w700).copyWith(color: cs.onSurface),
      h3: body(18, 1.4, weight: FontWeight.w600).copyWith(color: cs.onSurface),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 12),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 10),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 8),
      code: TextStyle(
        color: cs.onSurface,
        fontSize: 13,
        height: 1.7,
        fontWeight: FontWeight.w500,
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      listBullet: body(16, 1.65),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

class _StaggerReveal extends StatefulWidget {
  const _StaggerReveal({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(curve);
    _play();
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) {
      await Future.delayed(widget.delay);
    }
    if (mounted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final MarketAnalysis analysis;
  final String? coverImage;

  const _HeroHeader({required this.analysis, required this.coverImage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = const Color(0xFF10B981);

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverImage != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: coverImage!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      _imagePlaceholder(context, height: double.infinity),
                  errorWidget: (_, _, _) => _imageError(context),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: DateFormat(
                        'yyyy년 MM월 dd일',
                      ).format(analysis.createdAt),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  analysis.title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 3,
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

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onTap,
        icon: Icon(icon, size: 19, color: cs.onSurface.withValues(alpha: 0.78)),
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
        color: Color(0xFF10B981),
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
