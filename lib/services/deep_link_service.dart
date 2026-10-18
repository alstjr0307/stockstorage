import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../models/market_analysis.dart';
import '../models/stock_pick.dart';
import '../models/shared_stock_link.dart';
import '../models/shared_post_link.dart';
import 'shared_post_navigation.dart';
import 'analytics_service.dart';
import '../screens/market_analysis_detail_screen.dart';
import '../screens/stock_detail_screen.dart';
import '../services/firestore_service.dart';
import '../utils/globals.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static final _fs = FirestoreService();

  static const _host = 'stockstorage-13828.web.app';

  static Future<void> init() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleUri(initial);
    _sub = _appLinks.uriLinkStream.listen(_handleUri);
  }

  static void dispose() => _sub?.cancel();

  static void _handleUri(Uri uri) {
    if (uri.host != _host) return;
    final post = SharedPostLink.parse(uri);
    if (post != null) {
      unawaited(_navigateToPost(post.postId));
      return;
    }
    final stock = SharedStockLink.parse(uri);
    if (stock != null) {
      openSharedStock(stock);
      return;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      if (segments[0] == 'pick') _navigateToPick(segments[1]);
      if (segments[0] == 'analysis') _navigateToAnalysis(segments[1]);
    }
  }

  static Future<void> openSharedStock(SharedStockLink stock) async {
    // Initial app links can arrive before the root Navigator is attached.
    for (
      var attempt = 0;
      attempt < 50 && navigatorKey.currentState == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      AnalyticsService.instance.logStockJourney(
        'stock_share_landing',
        ticker: stock.ticker,
        market: stock.market,
        source: 'native_link',
      ),
    );
    navigator.push(
      stockDetailRoute(
        stockPickForGeneralDetail(
          ticker: stock.ticker,
          name: stock.name.isEmpty ? stock.ticker : stock.name,
          market: stock.market,
        ),
        enablePickFeatures: false,
      ),
    );
  }

  static Future<void> _navigateToPost(String postId) async {
    // Cold-start links may arrive before the root Navigator is mounted.
    for (
      var attempt = 0;
      attempt < 100 && navigatorKey.currentState == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final context = navigatorKey.currentState?.overlay?.context;
    if (context != null && context.mounted) {
      await openSharedPost(context, postId);
    }
  }

  static Future<void> _navigateToPick(String pickId) async {
    final pick = await _fs.getStockPickOnce(pickId);
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (pick == null) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('종목을 찾을 수 없습니다.')));
      return;
    }

    navigatorKey.currentState?.push(stockDetailRoute(pick));
  }

  static Future<void> _navigateToAnalysis(String analysisId) async {
    final analysis = await _fs.getMarketAnalysisOnce(analysisId);
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (analysis == null) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('시황 분석을 찾을 수 없습니다.')));
      return;
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MarketAnalysisDetailScreen(analysis: analysis),
      ),
    );
  }

  static String pickUrl(StockPick pick) => 'https://$_host/pick/${pick.id}';

  static String analysisUrl(MarketAnalysis a) =>
      'https://$_host/analysis/${a.id}';
}
