import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../models/market_analysis.dart';
import '../models/stock_pick.dart';
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
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      if (segments[0] == 'pick') _navigateToPick(segments[1]);
      if (segments[0] == 'analysis') _navigateToAnalysis(segments[1]);
    }
  }

  static Future<void> _navigateToPick(String pickId) async {
    final pick = await _fs.getStockPickOnce(pickId);
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

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
    if (ctx == null) return;

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
