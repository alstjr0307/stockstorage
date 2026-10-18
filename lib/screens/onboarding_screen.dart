import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/stock_price_service.dart';
import 'stock_search_screen.dart';

// Keep the existing key so returning guests do not repeat onboarding.
const _onboardingPrefsKey = 'onboarding_completed_v1';

Future<bool> shouldShowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingPrefsKey) != true;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingPrefsKey, true);
}

Future<void> _recordOnboarding(
  String event,
  Map<String, Object> parameters,
) async {
  await AnalyticsService.instance.logOnboarding(event, parameters);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.searchStocks = StockPriceService.searchStocks,
    this.recordEvent = _recordOnboarding,
  });

  /// Null means browse home; otherwise open this exact stock above home.
  final ValueChanged<StockSearchResult?> onComplete;
  final Future<List<StockSearchResult>> Function(String) searchStocks;
  final Future<void> Function(String, Map<String, Object>) recordEvent;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_record('onboarding_view', {'flow': 'stock_first_v1'}));
  }

  Future<void> _record(String event, Map<String, Object> parameters) async {
    try {
      await widget.recordEvent(event, parameters);
    } catch (_) {
      // Measurement failures must not prevent navigation.
    }
  }

  Future<void> _finish(StockSearchResult? stock) async {
    if (_finishing) return;
    _finishing = true;
    try {
      await markOnboardingComplete();
    } catch (_) {
      // A preferences failure should not trap the user on the welcome screen.
    }
    if (!mounted) return;
    unawaited(
      _record('onboarding_complete', {
        'flow': 'stock_first_v1',
        'action': stock == null ? 'browse' : 'select_stock',
        if (stock != null) 'ticker': stock.ticker,
        if (stock != null) 'market': stock.market,
      }),
    );
    widget.onComplete(stock);
  }

  @override
  Widget build(BuildContext context) => StockSearchScreen(
    title: '관심 있는 종목부터 찾아보세요',
    subtitle:
        '주식저장소에서 시세와 뉴스를 먼저 확인하세요.\n'
        '로그인은 관심종목에 저장할 때 하면 돼요.',
    backLabel: '먼저 홈 둘러보기',
    onBack: () => _finish(null),
    onPick: _finish,
    searchStocks: widget.searchStocks,
  );
}
