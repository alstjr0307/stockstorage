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

  static void invalidateCache(String symbol) => _cache.remove(symbol);

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

  /// 종가 배열 반환. range: 1mo/3mo/6mo/1y/3y/5y, interval: 1d/1wk/1mo
  static Future<List<double>> fetchHistory(String ticker, String market,
      {String range = '1mo', String interval = '1d'}) async {
    final result =
        await fetchHistoryDetailed(ticker, market, range: range, interval: interval);
    return result.map((e) => e.$2).toList();
  }

  /// OHLC 캔들 데이터 반환. 실패 시 빈 리스트.
  static Future<List<({DateTime date, double open, double high, double low, double close})>>
      fetchOHLC(String ticker, String market, {String interval = '1d', String range = '1mo'}) async {
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) return [];

      final timestamps = (result['timestamp'] as List<dynamic>?)
          ?.whereType<num>()
          .map((v) => DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000))
          .toList();
      final quote = result['indicators']?['quote']?[0];
      final opens = (quote?['open'] as List<dynamic>?)?.map((v) => v is num ? v.toDouble() : null).toList();
      final highs = (quote?['high'] as List<dynamic>?)?.map((v) => v is num ? v.toDouble() : null).toList();
      final lows = (quote?['low'] as List<dynamic>?)?.map((v) => v is num ? v.toDouble() : null).toList();
      final closes = (quote?['close'] as List<dynamic>?)?.map((v) => v is num ? v.toDouble() : null).toList();

      if (timestamps == null || opens == null || highs == null || lows == null || closes == null) return [];

      final out = <({DateTime date, double open, double high, double low, double close})>[];
      for (var i = 0; i < timestamps.length; i++) {
        final o = opens[i]; final h = highs[i]; final l = lows[i]; final c = closes[i];
        if (o != null && h != null && l != null && c != null) {
          out.add((date: timestamps[i], open: o, high: h, low: l, close: c));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 뉴스: 한국 종목은 Google News 한국어, 미국 종목은 Yahoo Finance
  static Future<List<StockNews>> fetchNews(String ticker, String market,
      {String? name}) async {
    if (market != 'US' && name != null && name.isNotEmpty) {
      return _fetchGoogleNewsKr(name);
    }
    return _fetchYahooNews(ticker, market);
  }

  static Future<List<StockNews>> _fetchGoogleNewsKr(String name) async {
    try {
      final query = Uri.encodeComponent('$name 주식');
      final uri = Uri.parse(
          'https://news.google.com/rss/search?q=$query&hl=ko&gl=KR&ceid=KR:ko');
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final body = response.body;
      final items = <StockNews>[];
      final itemPattern = RegExp(r'<item>([\s\S]*?)</item>');
      for (final match in itemPattern.allMatches(body).take(5)) {
        final item = match.group(1)!;
        // 제목 끝 " - 출처" 제거
        final title = _xmlTag(item, 'title')
            .replaceAll(RegExp(r'\s*-\s*[^-]+$'), '')
            .trim();
        final link = _xmlTag(item, 'link');
        final pubDateStr = _xmlTag(item, 'pubDate');
        final source = RegExp(r'<source[^>]*>([^<]*)</source>')
                .firstMatch(item)
                ?.group(1)
                ?.trim() ??
            '';
        if (title.isEmpty || link.isEmpty) continue;
        DateTime publishedAt;
        try {
          publishedAt = _parseRssDate(pubDateStr);
        } catch (_) {
          publishedAt = DateTime.now();
        }
        items.add(StockNews(
            title: title, url: link, publisher: source, publishedAt: publishedAt));
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static String _xmlTag(String xml, String tag) {
    final m = RegExp(
            '<$tag>(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([\\s\\S]*?))</$tag>')
        .firstMatch(xml);
    return (m?.group(1) ?? m?.group(2) ?? '').trim();
  }

  static DateTime _parseRssDate(String s) {
    // "Mon, 10 Mar 2026 10:00:00 GMT"
    final p = s.trim().split(' ');
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    };
    final day = int.tryParse(p[1]) ?? 1;
    final month = months[p[2]] ?? 1;
    final year = int.tryParse(p[3]) ?? 2024;
    final t = p.length > 4 ? p[4].split(':') : ['0', '0'];
    return DateTime.utc(year, month, day, int.tryParse(t[0]) ?? 0,
        int.tryParse(t.length > 1 ? t[1] : '0') ?? 0).toLocal();
  }

  static Future<List<StockNews>> _fetchYahooNews(
      String ticker, String market) async {
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v1/finance/search'
        '?q=${Uri.encodeComponent(symbol)}&quotesCount=0&newsCount=5',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final items = json['news'] as List<dynamic>? ?? [];
      return items
          .map((item) {
            if (item == null) return null;
            final title = item['title'] as String? ?? '';
            final url = item['link'] as String? ?? '';
            if (title.isEmpty || url.isEmpty) return null;
            final ts = item['providerPublishTime'] as int? ?? 0;
            return StockNews(
              title: title,
              url: url,
              publisher: item['publisher'] as String? ?? '',
              publishedAt: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            );
          })
          .whereType<StockNews>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Yahoo Finance 실적 발표 예정일 (US 종목만)
  static Future<DateTime?> fetchEarningsDate(String ticker, String market) async {
    if (market != 'US') return null;
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v10/finance/quoteSummary/$symbol'
        '?modules=calendarEvents',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      final dates = json['quoteSummary']?['result']?[0]
          ?['calendarEvents']?['earnings']?['earningsDate'] as List<dynamic>?;
      if (dates == null || dates.isEmpty) return null;
      final raw = dates[0]?['raw'] as int?;
      if (raw == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    } catch (_) {
      return null;
    }
  }

  /// (날짜, 종가) 배열 반환. 실패 시 빈 리스트.
  static Future<List<(DateTime, double)>> fetchHistoryDetailed(
      String ticker, String market,
      {String range = '1mo', String interval = '1d'}) async {
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) return [];

      final timestamps = (result['timestamp'] as List<dynamic>?)
          ?.whereType<num>()
          .map((v) => DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000))
          .toList();
      final closes =
          (result['indicators']?['quote']?[0]?['close'] as List<dynamic>?)
              ?.map((v) => v is num ? v.toDouble() : null)
              .toList();

      if (timestamps == null || closes == null) return [];

      final List<(DateTime, double)> out = [];
      for (var i = 0; i < timestamps.length && i < closes.length; i++) {
        final c = closes[i];
        if (c != null) out.add((timestamps[i], c));
      }
      return out;
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

class StockNews {
  final String title;
  final String url;
  final String publisher;
  final DateTime publishedAt;
  const StockNews({
    required this.title,
    required this.url,
    required this.publisher,
    required this.publishedAt,
  });
}
