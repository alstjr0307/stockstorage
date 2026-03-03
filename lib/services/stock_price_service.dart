import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class StockSearchResult {
  final String ticker;
  final String name;
  final String market; // KS, KQ, US
  final String exchange;

  const StockSearchResult({
    required this.ticker,
    required this.name,
    required this.market,
    required this.exchange,
  });

  static StockSearchResult? _fromSymbol(String symbol, String name, String exchange) {
    String ticker;
    String market;
    if (symbol.endsWith('.KS')) {
      ticker = symbol.replaceAll('.KS', '');
      market = 'KS';
    } else if (symbol.endsWith('.KQ')) {
      ticker = symbol.replaceAll('.KQ', '');
      market = 'KQ';
    } else if (!symbol.contains('.')) {
      ticker = symbol;
      market = 'US';
    } else {
      return null; // 다른 시장 제외
    }
    return StockSearchResult(ticker: ticker, name: name, market: market, exchange: exchange);
  }
}

class StockPriceService {
  static final _hasKorean = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');
  static final _isNumericCode = RegExp(r'^\d{4,6}$');

  /// 쿼리에 한글이 있거나 숫자 코드면 네이버, 아니면 Yahoo Finance
  static Future<List<StockSearchResult>> searchStocks(String query) async {
    if (query.isEmpty) return [];
    if (_hasKorean.hasMatch(query) || _isNumericCode.hasMatch(query)) {
      return _searchNaver(query);
    }
    return _searchYahoo(query);
  }

  /// 네이버 금융 자동완성 API (한국주식 한국어 이름)
  static Future<List<StockSearchResult>> _searchNaver(String query) async {
    try {
      final uri = Uri(
        scheme: 'https',
        host: 'ac.stock.naver.com',
        path: '/ac',
        queryParameters: {
          'q': query,
          'target': 'stock,index,etf,fund,exchange',
          'type': 'main',
        },
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://finance.naver.com',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);

      final items = json['items'] as List<dynamic>? ?? [];
      if (items.isEmpty) return [];

      return items
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final code = item['code'] as String? ?? '';
            final name = item['name'] as String? ?? '';
            final typeCode = (item['typeCode'] as String? ?? '').toUpperCase();
            final typeName = item['typeName'] as String? ?? '';

            if (code.isEmpty || name.isEmpty) return null;
            final String market;
            if (typeCode == 'KOSDAQ') {
              market = 'KQ';
            } else if (typeCode == 'KOSPI') {
              market = 'KS';
            } else {
              return null; // 지수, ETF, 펀드 등 제외
            }
            return StockSearchResult(ticker: code, name: name, market: market, exchange: typeName);
          })
          .whereType<StockSearchResult>()
          .toList();
    } catch (e, st) {
      debugPrint('[Naver] ERROR: $e');
      debugPrint('[Naver] $st');
      return [];
    }
  }

  /// Yahoo Finance 검색 API (미국주식)
  static Future<List<StockSearchResult>> _searchYahoo(String query) async {
    try {
      final uri = Uri.parse(
        'https://query2.finance.yahoo.com/v1/finance/search'
        '?q=${Uri.encodeComponent(query)}&quotesCount=10&newsCount=0',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final quotes = json['quotes'] as List<dynamic>? ?? [];

      return quotes
          .where((q) => q['quoteType'] == 'EQUITY')
          .map((q) {
            final symbol = q['symbol'] as String? ?? '';
            final name = (q['longname'] ?? q['shortname'] ?? symbol) as String;
            final exchange = (q['exchDisp'] ?? '') as String;
            return StockSearchResult._fromSymbol(symbol, name, exchange);
          })
          .whereType<StockSearchResult>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static final _cache = <String, _CachedPrice>{};
  static const _cacheDuration = Duration(minutes: 3);

  /// ticker + market으로 Yahoo Finance 심볼 생성
  static String toSymbol(String ticker, String market) {
    return switch (market) {
      'KS' => '$ticker.KS',
      'KQ' => '$ticker.KQ',
      _ => ticker, // US
    };
  }

  /// 현재가 반환. 실패 시 null.
  static Future<PriceResult?> fetchPrice(String ticker, String market) async {
    final symbol = toSymbol(ticker, market);

    // 캐시 확인
    final cached = _cache[symbol];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
      return cached.result;
    }

    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&range=1d',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final meta = json['chart']?['result']?[0]?['meta'];
      if (meta == null) return null;

      final price = (meta['regularMarketPrice'] as num?)?.toDouble();
      if (price == null) return null;

      final currency = meta['currency'] as String? ?? 'KRW';

      // 지수는 previousClose 대신 chartPreviousClose를 쓰거나
      // regularMarketChange/regularMarketChangePercent를 직접 제공
      final double change;
      final double changeRate;
      final directChange =
          (meta['regularMarketChange'] as num?)?.toDouble();
      final directChangeRate =
          (meta['regularMarketChangePercent'] as num?)?.toDouble();
      if (directChange != null && directChangeRate != null) {
        change = directChange;
        changeRate = directChangeRate;
      } else {
        final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ??
            (meta['previousClose'] as num?)?.toDouble() ??
            price;
        change = price - prevClose;
        changeRate = prevClose != 0 ? (change / prevClose) * 100 : 0.0;
      }

      final result = PriceResult(
        price: price,
        currency: currency,
        change: change,
        changeRate: changeRate,
      );

      _cache[symbol] = _CachedPrice(result: result, fetchedAt: DateTime.now());
      return result;
    } catch (_) {
      return null; // CORS(웹) 또는 네트워크 오류 시 null
    }
  }

  /// 1개월 일봉 종가 배열 반환. 실패 시 빈 리스트.
  static Future<List<double>> fetchHistory(String ticker, String market) async {
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&range=1mo',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) return [];

      final closes =
          (result['indicators']?['quote']?[0]?['close'] as List<dynamic>?)
              ?.whereType<num>()
              .map((v) => v.toDouble())
              .toList();
      return closes ?? [];
    } catch (_) {
      return [];
    }
  }
}

class PriceResult {
  final double price;
  final String currency; // 'KRW', 'USD'
  final double change;
  final double changeRate;

  const PriceResult({
    required this.price,
    required this.currency,
    required this.change,
    required this.changeRate,
  });

  bool get isUp => change >= 0;
  bool get isKrw => currency == 'KRW';

  String get formattedPrice {
    if (isKrw) {
      return '₩${price.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    }
    return '\$${price.toStringAsFixed(2)}';
  }

  String get formattedChange {
    final sign = isUp ? '+' : '';
    final rate = '$sign${changeRate.toStringAsFixed(2)}%';
    if (isKrw) {
      final amt = '$sign${change.toInt()}';
      return '$amt ($rate)';
    }
    return '$sign${change.toStringAsFixed(2)} ($rate)';
  }
}

class _CachedPrice {
  final PriceResult result;
  final DateTime fetchedAt;
  const _CachedPrice({required this.result, required this.fetchedAt});
}
