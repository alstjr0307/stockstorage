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

  static final _fundamentalsCache = <String, _CachedFundamentals>{};
  static const _fundamentalsCacheDuration = Duration(hours: 6);

  static _CachedFearAndGreed? _fearAndGreedCache;
  static const _fearAndGreedCacheDuration = Duration(minutes: 5);

  /// CNN Fear & Greed Index 반환. 실패 시 null. 5분 캐시.
  static Future<FearAndGreedResult?> fetchFearAndGreed() async {
    final cached = _fearAndGreedCache;
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _fearAndGreedCacheDuration) {
      return cached.result;
    }
    try {
      final uri = Uri.parse(
        'https://production.dataviz.cnn.io/index/fearandgreed/graphdata',
      );
      final response = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
        'Referer': 'https://www.cnn.com/markets/fear-and-greed',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      final fg = json['fear_and_greed'];
      if (fg == null) return null;

      final result = FearAndGreedResult(
        score: (fg['score'] as num).toDouble(),
        rating: fg['rating'] as String? ?? '',
        previousClose: (fg['previous_close'] as num).toDouble(),
        previousWeek: (fg['previous_1_week'] as num).toDouble(),
        previousMonth: (fg['previous_1_month'] as num).toDouble(),
        previousYear: (fg['previous_1_year'] as num).toDouble(),
      );
      _fearAndGreedCache = _CachedFearAndGreed(result: result, fetchedAt: DateTime.now());
      return result;
    } catch (_) {
      return null;
    }
  }

  // Yahoo Finance 크럼 캐시
  static String? _yahoocrumb;
  static String? _yahooCookie;

  /// PER / PBR 반환
  /// 한국(KS/KQ): sise.nhn(PER 실시간) + main.nhn(BPS) → PBR = 현재가/BPS
  /// 미국(US):    Yahoo Finance quoteSummary (crumb 방식)
  /// [currentPrice]: 한국주식 PBR 계산용 현재가 (없으면 PBR 생략)
  static Future<FundamentalsResult?> fetchFundamentals(
      String ticker, String market, {double? currentPrice}) async {
    final symbol = toSymbol(ticker, market);

    // 캐시는 가격 변동과 무관한 PER/BPS 기준으로 유지
    // currentPrice가 달라져도 캐시 무효화 안 함 (PER은 서버에서 이미 현재가 반영)
    final cached = _fundamentalsCache[symbol];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _fundamentalsCacheDuration) {
      // PBR은 현재가로 재계산
      if (currentPrice != null && cached.result.bps != null) {
        return FundamentalsResult(
          per: cached.result.per,
          pbr: currentPrice / cached.result.bps!,
          bps: cached.result.bps,
        );
      }
      return cached.result;
    }

    try {
      final FundamentalsResult? fundamentals;
      if (market == 'KS' || market == 'KQ') {
        fundamentals = await _fetchNaverFundamentals(ticker, currentPrice);
      } else {
        fundamentals = await _fetchYahooFundamentals(symbol);
      }
      if (fundamentals == null) return null;
      _fundamentalsCache[symbol] =
          _CachedFundamentals(result: fundamentals, fetchedAt: DateTime.now());
      return fundamentals;
    } catch (_) {
      return null;
    }
  }

  /// 네이버 금융:
  ///   PER  → sise.nhn (id="_sise_per", 현재가 기반 실시간)
  ///   BPS  → main.nhn (최근 연간 BPS)
  ///   PBR  → currentPrice / BPS
  static Future<FundamentalsResult?> _fetchNaverFundamentals(
      String ticker, double? currentPrice) async {
    // PER: sise.nhn
    final siseUri = Uri.parse('https://finance.naver.com/item/sise.nhn?code=$ticker');
    final siseRes = await http.get(siseUri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://finance.naver.com',
    }).timeout(const Duration(seconds: 8));

    double? per;
    if (siseRes.statusCode == 200) {
      final perMatch = RegExp(r'id="_sise_per"[^>]*>\s*([\d.,]+)')
          .firstMatch(siseRes.body);
      per = double.tryParse(perMatch?.group(1)?.replaceAll(',', '') ?? '');
    }

    // BPS: main.nhn
    double? bps;
    double? pbr;
    final mainUri = Uri.parse('https://finance.naver.com/item/main.nhn?code=$ticker');
    final mainRes = await http.get(mainUri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://finance.naver.com',
    }).timeout(const Duration(seconds: 8));

    if (mainRes.statusCode == 200) {
      final bpsMatch = RegExp(r'BPS\(\uc6d0\)</strong></th>[\s\S]{0,300}<td[^>]*>\s*([\d.,]+)')
          .firstMatch(mainRes.body);
      bps = double.tryParse(bpsMatch?.group(1)?.replaceAll(',', '') ?? '');
      if (bps != null && currentPrice != null) {
        pbr = currentPrice / bps;
      }
    }

    if (per == null && pbr == null) return null;
    return FundamentalsResult(per: per, pbr: pbr, bps: bps);
  }

  /// Yahoo Finance quoteSummary (crumb 방식, 미국주식)
  static Future<FundamentalsResult?> _fetchYahooFundamentals(String symbol) async {
    // 크럼이 없으면 발급
    if (_yahoocrumb == null) {
      final cookieRes = await http.get(
        Uri.parse('https://fc.yahoo.com'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 6));
      _yahooCookie = cookieRes.headers['set-cookie']
          ?.split(',')
          .map((c) => c.split(';').first.trim())
          .join('; ');

      final crumbRes = await http.get(
        Uri.parse('https://query2.finance.yahoo.com/v1/test/getcrumb'),
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Cookie': _yahooCookie ?? '',
        },
      ).timeout(const Duration(seconds: 6));
      _yahoocrumb = crumbRes.body.trim();
    }

    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v10/finance/quoteSummary/$symbol'
      '?modules=summaryDetail,defaultKeyStatistics&crumb=${Uri.encodeComponent(_yahoocrumb!)}',
    );
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Cookie': _yahooCookie ?? '',
    }).timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      // 크럼 만료 시 초기화 후 재시도
      _yahoocrumb = null;
      _yahooCookie = null;
      return null;
    }
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    final result = json['quoteSummary']?['result']?[0];
    if (result == null) return null;

    final per = (result['summaryDetail']?['trailingPE']?['raw'] as num?)?.toDouble();
    final pbr = (result['defaultKeyStatistics']?['priceToBook']?['raw'] as num?)?.toDouble();

    if (per == null && pbr == null) return null;
    return FundamentalsResult(per: per, pbr: pbr);
  }

  /// 네이버 종목토론방 게시글 (한국주식 전용, 최대 20개)
  static Future<List<DiscussionPost>> fetchDiscussionPosts(
      String ticker, String market) async {
    if (market != 'KS' && market != 'KQ') return [];
    try {
      final uri = Uri.parse(
          'https://finance.naver.com/item/board.nhn?code=$ticker&ordertype=&searchtype=&page=1');
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://finance.naver.com',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      // latin1로 디코딩 (EUC-KR 페이지를 latin1로 읽으면 한글 깨짐 → utf8 시도)
      String body;
      try {
        body = utf8.decode(response.bodyBytes);
      } catch (_) {
        body = response.body;
      }

      final rowPattern = RegExp(
        r'<tr onMouseOver[^>]*>[\s\S]*?'
        r'<span class="tah p10 gray03">(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2})</span>'
        r'[\s\S]*?nid=(\d+)[^"]*"[^>]*title="([^"]+)"'
        r'[\s\S]*?<td><span class="tah p10 gray03">(\d+)</span></td>',
      );

      final posts = <DiscussionPost>[];
      for (final m in rowPattern.allMatches(body)) {
        final dateParts = m.group(1)!.split(RegExp(r'[. :]'));
        final date = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(dateParts[3]),
          int.parse(dateParts[4]),
        );
        posts.add(DiscussionPost(
          nid: m.group(2)!,
          title: m.group(3)!,
          date: date,
          viewCount: int.tryParse(m.group(4)!) ?? 0,
          ticker: ticker,
        ));
      }
      return posts;
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

class FundamentalsResult {
  final double? per;
  final double? pbr;
  final double? bps;   // BPS 캐시용 (PBR 재계산에 사용)
  const FundamentalsResult({this.per, this.pbr, this.bps});
}

class _CachedFundamentals {
  final FundamentalsResult result;
  final DateTime fetchedAt;
  const _CachedFundamentals({required this.result, required this.fetchedAt});
}

class DiscussionPost {
  final String nid;
  final String title;
  final DateTime date;
  final int viewCount;
  final String ticker;

  const DiscussionPost({
    required this.nid,
    required this.title,
    required this.date,
    required this.viewCount,
    required this.ticker,
  });

  String get readUrl =>
      'https://finance.naver.com/item/board_read.naver?code=$ticker&nid=$nid&page=1';
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

class FearAndGreedResult {
  final double score;
  final String rating;
  final double previousClose;
  final double previousWeek;
  final double previousMonth;
  final double previousYear;

  const FearAndGreedResult({
    required this.score,
    required this.rating,
    required this.previousClose,
    required this.previousWeek,
    required this.previousMonth,
    required this.previousYear,
  });
}

class _CachedFearAndGreed {
  final FearAndGreedResult result;
  final DateTime fetchedAt;
  const _CachedFearAndGreed({required this.result, required this.fetchedAt});
}
