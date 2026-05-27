import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
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

  static StockSearchResult? _fromSymbol(
    String symbol,
    String name,
    String exchange,
  ) {
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
    return StockSearchResult(
      ticker: ticker,
      name: name,
      market: market,
      exchange: exchange,
    );
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
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));

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
            return StockSearchResult(
              ticker: code,
              name: name,
              market: market,
              exchange: typeName,
            );
          })
          .whereType<StockSearchResult>()
          .toList();
    } catch (_) {
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
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 6));

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
  static const _domesticRealtimeCacheDuration = Duration(seconds: 5);
  static const _ohlcCacheDuration = Duration(minutes: 3);

  static double _applyNaverDirection(double value, dynamic compareInfo) {
    if (value == 0) return 0.0;
    final info = compareInfo is Map ? compareInfo : null;
    final code = (info?['code'] as String? ?? '').trim();
    final name = (info?['name'] as String? ?? '').toUpperCase().trim();
    final text = (info?['text'] as String? ?? '').trim();
    final isDown =
        code == '5' ||
        name == 'FALLING' ||
        name == 'LOWER' ||
        text.contains('하락');
    return isDown ? -value.abs() : value.abs();
  }

  static void invalidateCache(String symbol) {
    _cache.remove(symbol);
    _ohlcCache.removeWhere((k, _) => k.startsWith('$symbol:'));
    _ohlcCacheFetchedAt.removeWhere((k, _) => k.startsWith('$symbol:'));
  }

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
    final cacheDuration = {'KS', 'KQ'}.contains(market)
        ? _domesticRealtimeCacheDuration
        : _cacheDuration;

    // 캐시 확인
    final cached = _cache[symbol];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheDuration) {
      return cached.result;
    }

    if ({'KS', 'KQ'}.contains(market)) {
      final result = await _fetchNaverStockPrice(ticker);
      if (result != null) {
        _cache[symbol] = _CachedPrice(
          result: result,
          fetchedAt: DateTime.now(),
        );
        return result;
      }

      final kisResult = await _fetchKisDomesticPrice(ticker);
      if (kisResult != null) {
        _cache[symbol] = _CachedPrice(
          result: kisResult,
          fetchedAt: DateTime.now(),
        );
        return kisResult;
      }
    }

    // 한국 주요 지수는 네이버 realtime API 우선
    final naverSym = _naverSymbols[symbol];
    if (naverSym != null) {
      final result = await _fetchNaverIndexPrice(naverSym);
      if (result != null) {
        _cache[symbol] = _CachedPrice(
          result: result,
          fetchedAt: DateTime.now(),
        );
        return result;
      }
    }

    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&range=1d',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));

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
      final directChange = (meta['regularMarketChange'] as num?)?.toDouble();
      if (directChange != null) {
        final prevClose =
            (meta['regularMarketPreviousClose'] as num?)?.toDouble() ??
            (meta['chartPreviousClose'] as num?)?.toDouble() ??
            (meta['previousClose'] as num?)?.toDouble();
        change = directChange;
        if (prevClose != null && prevClose != 0) {
          changeRate = (change / prevClose) * 100;
        } else {
          changeRate =
              (meta['regularMarketChangePercent'] as num?)?.toDouble() ?? 0.0;
        }
      } else {
        final prevClose =
            (meta['regularMarketPreviousClose'] as num?)?.toDouble() ??
            (meta['chartPreviousClose'] as num?)?.toDouble() ??
            (meta['previousClose'] as num?)?.toDouble() ??
            price;
        change = price - prevClose;
        changeRate = prevClose != 0 ? (change / prevClose) * 100 : 0.0;
      }

      final marketTimeRaw = meta['regularMarketTime'] as int?;
      final marketTime = marketTimeRaw != null
          ? DateTime.fromMillisecondsSinceEpoch(
              marketTimeRaw * 1000,
              isUtc: true,
            ).add(const Duration(hours: 9)) // KST = UTC+9
          : null;

      final result = PriceResult(
        price: price,
        currency: currency,
        change: change,
        changeRate: changeRate,
        marketTime: marketTime,
      );

      _cache[symbol] = _CachedPrice(result: result, fetchedAt: DateTime.now());
      return result;
    } catch (_) {
      return null; // CORS(웹) 또는 네트워크 오류 시 null
    }
  }

  /// 종가 배열 반환. range: 1mo/3mo/6mo/1y/3y/5y, interval: 1d/1wk/1mo
  static Future<List<double>> fetchHistory(
    String ticker,
    String market, {
    String range = '1mo',
    String interval = '1d',
  }) async {
    final result = await fetchHistoryDetailed(
      ticker,
      market,
      range: range,
      interval: interval,
    );
    return result.map((e) => e.$2).toList();
  }

  static final _ohlcCache =
      <
        String,
        List<
          ({DateTime date, double open, double high, double low, double close})
        >
      >{};
  static final _ohlcCacheFetchedAt = <String, DateTime>{};

  static final _naverSymbols = {'^KS11': 'KOSPI', '^KQ11': 'KOSDAQ'};

  static int _rangeToDays(String range) => switch (range) {
    '1d' => 1,
    '5d' => 5,
    '1mo' => 31,
    '3mo' => 91,
    '6mo' => 182,
    '1y' => 365,
    '2y' => 730,
    '3y' => 1095,
    '5y' => 1826,
    _ => 7300, // max
  };

  static Future<PriceResult?> _fetchNaverIndexPrice(String naverSymbol) async {
    try {
      final uri = Uri.parse(
        'https://polling.finance.naver.com/api/realtime/domestic/index/$naverSymbol',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final rootDatas = (json['datas'] as List?)?.whereType<Map>();
      final areaDatas = (json['result']?['areas'] as List?)
          ?.whereType<Map>()
          .expand((a) => (a['datas'] as List?) ?? [])
          .whereType<Map>();
      final item = (rootDatas == null || rootDatas.isEmpty)
          ? areaDatas?.firstOrNull
          : rootDatas.firstOrNull;
      if (item == null) return null;

      double parse(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0.0;
      final price = parse(item['closePrice'] as String? ?? '');
      if (price == 0) return null;

      final rawChange = parse(
        item['compareToPreviousClosePrice'] as String? ?? '',
      );
      final change = _applyNaverDirection(
        rawChange,
        item['compareToPreviousPrice'],
      );
      final changeRate =
          double.tryParse(
            (item['fluctuationsRatio'] as String? ?? '').replaceAll(',', ''),
          ) ??
          0.0;

      final tradedAtStr = item['localTradedAt'] as String? ?? '';
      final marketTime = DateTime.tryParse(tradedAtStr)?.toLocal();

      return PriceResult(
        price: price,
        currency: 'KRW',
        change: change,
        changeRate: changeRate,
        marketTime: marketTime,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<PriceResult?> _fetchNaverStockPrice(String ticker) async {
    try {
      final uri = Uri.parse(
        'https://polling.finance.naver.com/api/realtime/domestic/stock/$ticker',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final item = (json['datas'] as List?)?.whereType<Map>().firstOrNull;
      if (item == null) return null;

      double parse(String? s) =>
          double.tryParse((s ?? '').replaceAll(',', '')) ?? 0.0;
      final over = item['overMarketPriceInfo'] as Map?;
      final overPrice = parse(over?['overPrice'] as String?);
      final overRawChange = parse(
        over?['compareToPreviousClosePrice'] as String?,
      );
      final overChange = _applyNaverDirection(
        overRawChange,
        over?['compareToPreviousPrice'],
      );
      final overRate =
          double.tryParse(
            (over?['fluctuationsRatio'] as String? ?? '').replaceAll(',', ''),
          ) ??
          0.0;
      final overTradedAt = DateTime.tryParse(
        over?['localTradedAt'] as String? ?? '',
      )?.toLocal();

      final regularPrice = parse(
        item['closePriceRaw'] as String? ?? item['closePrice'] as String? ?? '',
      );
      final price = overPrice > 0 ? overPrice : regularPrice;
      if (price == 0) return null;

      final rawChange = overPrice > 0
          ? overChange
          : parse(
              item['compareToPreviousClosePriceRaw'] as String? ??
                  item['compareToPreviousClosePrice'] as String? ??
                  '',
            );
      final change = overPrice > 0
          ? rawChange
          : _applyNaverDirection(rawChange, item['compareToPreviousPrice']);
      final changeRate = overPrice > 0
          ? overRate
          : double.tryParse(
                  (item['fluctuationsRatioRaw'] as String? ??
                          item['fluctuationsRatio'] as String? ??
                          '')
                      .replaceAll(',', ''),
                ) ??
                0.0;
      final regularTradedAt = DateTime.tryParse(
        item['localTradedAt'] as String? ?? '',
      )?.toLocal();
      final marketTime = overTradedAt ?? regularTradedAt;

      return PriceResult(
        price: price,
        currency: 'KRW',
        change: change,
        changeRate: changeRate,
        marketTime: marketTime,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<PriceResult?> _fetchKisDomesticPrice(String ticker) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable(
            'getKisDomesticQuote',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
          );
      final res = await fn.call({'ticker': ticker});
      final d = res.data as Map<String, dynamic>;
      if (d['hasData'] == false) return null;

      final price = (d['price'] as num?)?.toDouble();
      if (price == null || price <= 0) return null;
      final change = (d['change'] as num?)?.toDouble() ?? 0.0;
      final changeRate = (d['changeRate'] as num?)?.toDouble() ?? 0.0;

      return PriceResult(
        price: price,
        currency: 'KRW',
        change: change,
        changeRate: changeRate,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _patchDomesticMinuteCandle(
    List<({DateTime date, double open, double high, double low, double close})>
    out,
    String ticker,
    String interval,
  ) async {
    final minuteUnit = switch (interval) {
      '1m' => 1,
      '5m' => 5,
      '60m' => 60,
      _ => 0,
    };
    if (minuteUnit == 0) return;

    try {
      final uri = Uri.parse(
        'https://polling.finance.naver.com/api/realtime/domestic/stock/$ticker',
      );
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body);
      final item = (json['datas'] as List?)?.whereType<Map>().firstOrNull;
      if (item == null) return;

      double parseNum(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString().replaceAll(',', '')) ?? 0.0;
      }

      DateTime? parseTime(dynamic v) {
        if (v == null) return null;
        return DateTime.tryParse(v.toString())?.toLocal();
      }

      final over = item['overMarketPriceInfo'] as Map?;
      final integrated = item['integratedPriceInfo'] as Map?;

      final overTradedAt = parseTime(over?['localTradedAt']);
      final regularTradedAt = parseTime(item['localTradedAt']);
      final overClose = parseNum(over?['overPrice']);
      DateTime? tradedAt = overTradedAt ?? regularTradedAt;
      // some responses have overPrice but miss over-market traded time.
      // in that case, promote bucket to current time so post-market candle appears.
      if (overClose > 0 && overTradedAt == null && tradedAt != null) {
        final now = DateTime.now();
        final sameDay =
            now.year == tradedAt.year &&
            now.month == tradedAt.month &&
            now.day == tradedAt.day;
        final weekday =
            now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
        final afterRegularClose =
            now.hour > 15 || (now.hour == 15 && now.minute >= 30);
        if (sameDay && weekday && afterRegularClose) {
          tradedAt = now;
        }
      }
      if (tradedAt == null) return;

      final close = overClose > 0
          ? overClose
          : parseNum(item['closePriceRaw'] ?? item['closePrice'] ?? '');
      if (close <= 0) return;

      final highCandidate = parseNum(
        integrated?['highPrice'] ??
            over?['highPrice'] ??
            item['highPriceRaw'] ??
            item['highPrice'],
      );
      final lowCandidate = parseNum(
        integrated?['lowPrice'] ??
            over?['lowPrice'] ??
            item['lowPriceRaw'] ??
            item['lowPrice'],
      );
      final high = highCandidate > 0 ? highCandidate : close;
      final low = lowCandidate > 0 ? lowCandidate : close;

      final minuteBucket = (tradedAt.minute ~/ minuteUnit) * minuteUnit;
      final bucket = DateTime(
        tradedAt.year,
        tradedAt.month,
        tradedAt.day,
        tradedAt.hour,
        minuteBucket,
      );

      if (out.isEmpty) {
        out.add((
          date: bucket,
          open: close,
          high: high,
          low: low,
          close: close,
        ));
        return;
      }

      final last = out.last;
      if (last.date.isAtSameMomentAs(bucket)) {
        out[out.length - 1] = (
          date: bucket,
          open: last.open,
          high: last.high > high ? last.high : high,
          low: last.low < low ? last.low : low,
          close: close,
        );
        return;
      }

      if (last.date.isBefore(bucket)) {
        out.add((
          date: bucket,
          open: close,
          high: high,
          low: low,
          close: close,
        ));
      }
    } catch (_) {}
  }

  static Future<void> _forceAppendDomesticAfterHoursMinuteCandle(
    List<({DateTime date, double open, double high, double low, double close})>
    out,
    String ticker,
    String interval,
  ) async {
    final minuteUnit = switch (interval) {
      '1m' => 1,
      '5m' => 5,
      '60m' => 60,
      _ => 0,
    };
    if (minuteUnit == 0) return;

    final now = DateTime.now();
    final weekday =
        now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
    final afterRegularClose =
        now.hour > 15 || (now.hour == 15 && now.minute >= 30);
    if (!weekday || !afterRegularClose) return;

    final price = await _fetchNaverStockPrice(ticker);
    if (price == null || price.price <= 0) return;

    final minuteBucket = (now.minute ~/ minuteUnit) * minuteUnit;
    final bucket = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      minuteBucket,
    );
    final close = price.price;

    if (out.isEmpty) {
      out.add((
        date: bucket,
        open: close,
        high: close,
        low: close,
        close: close,
      ));
      return;
    }

    final last = out.last;
    final lastBucket = DateTime(
      last.date.year,
      last.date.month,
      last.date.day,
      last.date.hour,
      (last.date.minute ~/ minuteUnit) * minuteUnit,
    );
    if (bucket.isAfter(lastBucket)) {
      out.add((
        date: bucket,
        open: close,
        high: close,
        low: close,
        close: close,
      ));
    } else if (bucket.isAtSameMomentAs(lastBucket)) {
      out[out.length - 1] = (
        date: last.date,
        open: last.open,
        high: last.high > close ? last.high : close,
        low: last.low < close ? last.low : close,
        close: close,
      );
    }
  }

  static Future<
    List<({DateTime date, double open, double high, double low, double close})>
  >
  _fetchNaverDailyOHLC(
    String naverSymbol,
    String range, {
    bool isIndex = false,
  }) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: _rangeToDays(range)));
    String pad(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime d) => '${d.year}${pad(d.month)}${pad(d.day)}';
    final uri = Uri.parse(
      'https://api.finance.naver.com/siseJson.naver'
      '?symbol=$naverSymbol&requestType=1'
      '&startTime=${fmt(start)}&endTime=${fmt(end)}&timeframe=day',
    );
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final body = response.body;
      // format: ["YYYYMMDD", open, high, low, close, ...]
      final rowRegex = RegExp(
        r'\["(\d{8})",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)',
      );
      final out =
          <
            ({
              DateTime date,
              double open,
              double high,
              double low,
              double close,
            })
          >[];
      for (final m in rowRegex.allMatches(body)) {
        final d = m.group(1)!;
        final year = int.parse(d.substring(0, 4));
        final month = int.parse(d.substring(4, 6));
        final day = int.parse(d.substring(6, 8));
        final o = double.parse(m.group(2)!);
        final h = double.parse(m.group(3)!);
        final l = double.parse(m.group(4)!);
        final c = double.parse(m.group(5)!);
        out.add((
          date: DateTime(year, month, day),
          open: o,
          high: h,
          low: l,
          close: c,
        ));
      }

      // 지수: 오늘 캔들이 없으면 네이버 실시간 API로 보완 (장중/당일 종가 미반영)
      if (isIndex && out.isNotEmpty) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final lastDate = DateTime(
          out.last.date.year,
          out.last.date.month,
          out.last.date.day,
        );
        if (lastDate.isBefore(todayDate)) {
          try {
            final rtUri = Uri.parse(
              'https://polling.finance.naver.com/api/realtime/domestic/index/$naverSymbol',
            );
            final rtRes = await http
                .get(
                  rtUri,
                  headers: {
                    'User-Agent': 'Mozilla/5.0',
                    'Referer': 'https://finance.naver.com',
                  },
                )
                .timeout(const Duration(seconds: 5));
            if (rtRes.statusCode == 200) {
              final rtJson = jsonDecode(rtRes.body);
              final item = (rtJson['datas'] as List?)?.firstOrNull;
              if (item != null) {
                // localTradedAt이 오늘 날짜인지 확인 (주말/공휴일 가짜 캔들 방지)
                final tradedAtStr = item['localTradedAt'] as String? ?? '';
                final tradedAt = DateTime.tryParse(tradedAtStr)?.toLocal();
                final tradedDate = tradedAt == null
                    ? null
                    : DateTime(tradedAt.year, tradedAt.month, tradedAt.day);
                if (tradedDate != null &&
                    tradedDate.isAtSameMomentAs(todayDate)) {
                  double parse(String s) =>
                      double.tryParse(s.replaceAll(',', '')) ?? 0.0;
                  final o = parse(item['openPrice'] as String? ?? '');
                  final h = parse(item['highPrice'] as String? ?? '');
                  final l = parse(item['lowPrice'] as String? ?? '');
                  final c = parse(item['closePriceRaw'] as String? ?? '');
                  if (o > 0 && h > 0 && l > 0 && c > 0) {
                    out.add((
                      date: todayDate,
                      open: o,
                      high: h,
                      low: l,
                      close: c,
                    ));
                  }
                }
              }
            }
          } catch (_) {}
        }
      }

      if (!isIndex && out.isNotEmpty) {
        try {
          final rtUri = Uri.parse(
            'https://polling.finance.naver.com/api/realtime/domestic/stock/$naverSymbol',
          );
          final rtRes = await http
              .get(
                rtUri,
                headers: {
                  'User-Agent': 'Mozilla/5.0',
                  'Referer': 'https://finance.naver.com',
                },
              )
              .timeout(const Duration(seconds: 5));
          if (rtRes.statusCode == 200) {
            final rtJson = jsonDecode(rtRes.body);
            final item = (rtJson['datas'] as List?)
                ?.whereType<Map>()
                .firstOrNull;
            if (item != null) {
              final over = item['overMarketPriceInfo'] as Map?;
              final integrated = item['integratedPriceInfo'] as Map?;
              final overTradedAt = DateTime.tryParse(
                over?['localTradedAt'] as String? ?? '',
              )?.toLocal();
              final regularTradedAt = DateTime.tryParse(
                item['localTradedAt'] as String? ?? '',
              )?.toLocal();
              final tradedAt = overTradedAt ?? regularTradedAt;
              final tradedDate = tradedAt == null
                  ? null
                  : DateTime(tradedAt.year, tradedAt.month, tradedAt.day);
              if (tradedDate != null) {
                double parse(String? s) =>
                    double.tryParse((s ?? '').replaceAll(',', '')) ?? 0.0;
                final overClose = parse(over?['overPrice'] as String?);
                final o = parse(
                  item['openPriceRaw'] as String? ??
                      item['openPrice'] as String? ??
                      '',
                );
                final h = parse(
                  integrated?['highPrice'] as String? ??
                      over?['highPrice'] as String? ??
                      item['highPriceRaw'] as String? ??
                      item['highPrice'] as String? ??
                      '',
                );
                final l = parse(
                  integrated?['lowPrice'] as String? ??
                      over?['lowPrice'] as String? ??
                      item['lowPriceRaw'] as String? ??
                      item['lowPrice'] as String? ??
                      '',
                );
                final c = overClose > 0
                    ? overClose
                    : parse(
                        item['closePriceRaw'] as String? ??
                            item['closePrice'] as String? ??
                            '',
                      );
                if (o > 0 && h > 0 && l > 0 && c > 0) {
                  final candle = (
                    date: tradedDate,
                    open: o,
                    high: h,
                    low: l,
                    close: c,
                  );
                  final lastDate = DateTime(
                    out.last.date.year,
                    out.last.date.month,
                    out.last.date.day,
                  );
                  if (lastDate.isAtSameMomentAs(tradedDate)) {
                    out[out.length - 1] = candle;
                  } else if (lastDate.isBefore(tradedDate)) {
                    out.add(candle);
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      return out;
    } catch (_) {
      return [];
    }
  }

  /// OHLC 캔들 데이터 반환. 실패 시 빈 리스트.
  static Future<
    List<({DateTime date, double open, double high, double low, double close})>
  >
  fetchOHLC(
    String ticker,
    String market, {
    String interval = '1d',
    String range = '1mo',
  }) async {
    final symbol = toSymbol(ticker, market);
    final isDomestic = {'KS', 'KQ'}.contains(market);
    final isDomesticMinute =
        isDomestic &&
        (interval == '1m' || interval == '5m' || interval == '60m');
    final fastDomesticInterval =
        interval == '1m' ||
        interval == '5m' ||
        interval == '60m' ||
        interval == '1d';
    final ohlcCacheDuration = isDomestic && fastDomesticInterval
        ? const Duration(seconds: 20)
        : _ohlcCacheDuration;

    // 한국 개별 종목 일봉은 네이버 우선 (Yahoo 일봉 1일 지연 대응)
    if (interval == '1d' && {'KS', 'KQ'}.contains(market)) {
      final cacheKey = '$ticker:naver_stock:$interval:$range';
      final stockFetchedAt = _ohlcCacheFetchedAt[cacheKey];
      if (_ohlcCache.containsKey(cacheKey) &&
          stockFetchedAt != null &&
          DateTime.now().difference(stockFetchedAt) < ohlcCacheDuration) {
        return _ohlcCache[cacheKey]!;
      }
      final naverData = await _fetchNaverDailyOHLC(ticker, range);
      if (naverData.isNotEmpty) {
        _ohlcCache[cacheKey] = naverData;
        _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
        return naverData;
      }
    }

    // 코스피/코스닥 일봉은 네이버 파이낸스 우선 사용 (Yahoo Finance 누락 대응)
    if (interval == '1d' && _naverSymbols.containsKey(ticker)) {
      final naverSymbol = _naverSymbols[ticker]!;
      final cacheKey = '$ticker:naver:$interval:$range';
      final naverFetchedAt = _ohlcCacheFetchedAt[cacheKey];
      if (_ohlcCache.containsKey(cacheKey) &&
          naverFetchedAt != null &&
          DateTime.now().difference(naverFetchedAt) < ohlcCacheDuration) {
        return _ohlcCache[cacheKey]!;
      }
      final naverData = await _fetchNaverDailyOHLC(
        naverSymbol,
        range,
        isIndex: true,
      );
      if (naverData.isNotEmpty) {
        _ohlcCache[cacheKey] = naverData;
        _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
        return naverData;
      }
    }
    final cacheKey = '$symbol:$interval:$range';
    final fetchedAt = _ohlcCacheFetchedAt[cacheKey];
    if (!isDomesticMinute &&
        _ohlcCache.containsKey(cacheKey) &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < ohlcCacheDuration) {
      return _ohlcCache[cacheKey]!;
    }
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (isDomestic &&
            (interval == '1m' || interval == '5m' || interval == '60m')) {
          final fallback =
              <
                ({
                  DateTime date,
                  double open,
                  double high,
                  double low,
                  double close,
                })
              >[];
          await _patchDomesticMinuteCandle(fallback, ticker, interval);
          if (fallback.isNotEmpty) {
            _ohlcCache[cacheKey] = fallback;
            _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
          }
          return fallback;
        }
        return [];
      }
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) {
        if (isDomestic &&
            (interval == '1m' || interval == '5m' || interval == '60m')) {
          final fallback =
              <
                ({
                  DateTime date,
                  double open,
                  double high,
                  double low,
                  double close,
                })
              >[];
          await _patchDomesticMinuteCandle(fallback, ticker, interval);
          if (fallback.isNotEmpty) {
            _ohlcCache[cacheKey] = fallback;
            _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
          }
          return fallback;
        }
        return [];
      }

      final timestamps = (result['timestamp'] as List<dynamic>?)
          ?.whereType<num>()
          .map(
            (v) => DateTime.fromMillisecondsSinceEpoch(
              v.toInt() * 1000,
              isUtc: true,
            ).add(const Duration(hours: 9)),
          )
          .toList();
      final quote = result['indicators']?['quote']?[0];
      final opens = (quote?['open'] as List<dynamic>?)
          ?.map((v) => v is num ? v.toDouble() : null)
          .toList();
      final highs = (quote?['high'] as List<dynamic>?)
          ?.map((v) => v is num ? v.toDouble() : null)
          .toList();
      final lows = (quote?['low'] as List<dynamic>?)
          ?.map((v) => v is num ? v.toDouble() : null)
          .toList();
      final closes = (quote?['close'] as List<dynamic>?)
          ?.map((v) => v is num ? v.toDouble() : null)
          .toList();

      if (timestamps == null ||
          opens == null ||
          highs == null ||
          lows == null ||
          closes == null) {
        if (isDomestic &&
            (interval == '1m' || interval == '5m' || interval == '60m')) {
          final fallback =
              <
                ({
                  DateTime date,
                  double open,
                  double high,
                  double low,
                  double close,
                })
              >[];
          await _patchDomesticMinuteCandle(fallback, ticker, interval);
          if (fallback.isNotEmpty) {
            _ohlcCache[cacheKey] = fallback;
            _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
          }
          return fallback;
        }
        return [];
      }

      final out =
          <
            ({
              DateTime date,
              double open,
              double high,
              double low,
              double close,
            })
          >[];
      for (var i = 0; i < timestamps.length; i++) {
        final o = opens[i];
        final h = highs[i];
        final l = lows[i];
        final c = closes[i];
        if (o != null &&
            h != null &&
            l != null &&
            c != null &&
            o > 0 &&
            h > 0 &&
            l > 0 &&
            c > 0) {
          out.add((date: timestamps[i], open: o, high: h, low: l, close: c));
        }
      }
      // 일봉 요청 시 Yahoo Finance가 당일 진행 중인 캔들을 누락하는 경우
      // range=5d 보조 요청으로 당일 캔들을 추가
      if (interval == '1d' && out.isNotEmpty) {
        final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
        final todayDate = DateTime(nowKst.year, nowKst.month, nowKst.day);
        final lastDate = DateTime(
          out.last.date.year,
          out.last.date.month,
          out.last.date.day,
        );
        if (lastDate.isBefore(todayDate)) {
          try {
            final supUri = Uri.parse(
              'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
              '?interval=1d&range=5d',
            );
            final supRes = await http
                .get(supUri, headers: {'User-Agent': 'Mozilla/5.0'})
                .timeout(const Duration(seconds: 8));
            if (supRes.statusCode == 200) {
              final supJson = jsonDecode(supRes.body);
              final supResult = supJson['chart']?['result']?[0];
              if (supResult != null) {
                final supTs = (supResult['timestamp'] as List<dynamic>?)
                    ?.whereType<num>()
                    .map(
                      (v) => DateTime.fromMillisecondsSinceEpoch(
                        v.toInt() * 1000,
                        isUtc: true,
                      ).add(const Duration(hours: 9)),
                    )
                    .toList();
                final supQ = supResult['indicators']?['quote']?[0];
                final supO = (supQ?['open'] as List<dynamic>?)
                    ?.map((v) => v is num ? v.toDouble() : null)
                    .toList();
                final supH = (supQ?['high'] as List<dynamic>?)
                    ?.map((v) => v is num ? v.toDouble() : null)
                    .toList();
                final supL = (supQ?['low'] as List<dynamic>?)
                    ?.map((v) => v is num ? v.toDouble() : null)
                    .toList();
                final supC = (supQ?['close'] as List<dynamic>?)
                    ?.map((v) => v is num ? v.toDouble() : null)
                    .toList();
                if (supTs != null &&
                    supO != null &&
                    supH != null &&
                    supL != null &&
                    supC != null) {
                  for (var i = 0; i < supTs.length; i++) {
                    final d = DateTime(
                      supTs[i].year,
                      supTs[i].month,
                      supTs[i].day,
                    );
                    if (d.isAfter(lastDate)) {
                      final o = supO[i];
                      final h = supH[i];
                      final l = supL[i];
                      final c = supC[i];
                      if (o != null &&
                          h != null &&
                          l != null &&
                          c != null &&
                          o > 0 &&
                          h > 0 &&
                          l > 0 &&
                          c > 0) {
                        out.add((
                          date: supTs[i],
                          open: o,
                          high: h,
                          low: l,
                          close: c,
                        ));
                      }
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }
      }

      if (isDomestic &&
          (interval == '1m' || interval == '5m' || interval == '60m')) {
        await _patchDomesticMinuteCandle(out, ticker, interval);
        await _forceAppendDomesticAfterHoursMinuteCandle(out, ticker, interval);
      }

      if (out.isNotEmpty) {
        _ohlcCache[cacheKey] = out;
        _ohlcCacheFetchedAt[cacheKey] = DateTime.now();
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 뉴스: 한국 종목은 Google News 한국어, 미국 종목은 Yahoo Finance
  static Future<List<StockNews>> fetchNews(
    String ticker,
    String market, {
    String? name,
  }) async {
    if (market != 'US' && name != null && name.isNotEmpty) {
      return _fetchGoogleNewsKr(name);
    }
    return _fetchYahooNews(ticker, market);
  }

  static Future<List<StockNews>> _fetchGoogleNewsKr(String name) async {
    try {
      final query = Uri.encodeComponent('$name 주식');
      final uri = Uri.parse(
        'https://news.google.com/rss/search?q=$query&hl=ko&gl=KR&ceid=KR:ko',
      );
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
        final title = _xmlTag(
          item,
          'title',
        ).replaceAll(RegExp(r'\s*-\s*[^-]+$'), '').trim();
        final link = _xmlTag(item, 'link');
        final pubDateStr = _xmlTag(item, 'pubDate');
        final source =
            RegExp(
              r'<source[^>]*>([^<]*)</source>',
            ).firstMatch(item)?.group(1)?.trim() ??
            '';
        if (title.isEmpty || link.isEmpty) continue;
        DateTime publishedAt;
        try {
          publishedAt = _parseRssDate(pubDateStr);
        } catch (_) {
          publishedAt = DateTime.now();
        }
        items.add(
          StockNews(
            title: title,
            url: link,
            publisher: source,
            publishedAt: publishedAt,
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<StockAiAnalysisResult> generateStockAiAnalysis({
    required String ticker,
    required String name,
    required String market,
    PriceResult? price,
    FundamentalsResult? fundamentals,
    required List<Map<String, dynamic>> candles,
    required List<StockNews> news,
  }) async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable(
          'generateStockAiAnalysis',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        );
    final res = await fn.call({
      'stock': {'ticker': ticker, 'name': name, 'market': market},
      'price': {
        if (price != null) ...{
          'currentPrice': price.price,
          'change': price.change,
          'changeRate': price.changeRate,
        },
      },
      'fundamentals': {
        if (fundamentals?.per != null) 'per': fundamentals!.per,
        if (fundamentals?.pbr != null) 'pbr': fundamentals!.pbr,
        if (fundamentals?.bps != null) 'bps': fundamentals!.bps,
        if (fundamentals?.marketCap != null)
          'marketCap': fundamentals!.marketCap,
        if (fundamentals?.forwardPer != null)
          'forwardPer': fundamentals!.forwardPer,
        if (fundamentals?.sectorAveragePer != null)
          'sectorAveragePer': fundamentals!.sectorAveragePer,
      },
      'candles': candles,
      'news': news
          .map(
            (n) => {
              'title': n.title,
              'url': n.url,
              'publisher': n.publisher,
              'publishedAt': n.publishedAt.toIso8601String(),
            },
          )
          .toList(),
    });
    return StockAiAnalysisResult.fromMap(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  static String _xmlTag(String xml, String tag) {
    final m = RegExp(
      '<$tag>(?:<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>|([\\s\\S]*?))</$tag>',
    ).firstMatch(xml);
    return (m?.group(1) ?? m?.group(2) ?? '').trim();
  }

  static DateTime _parseRssDate(String s) {
    // "Mon, 10 Mar 2026 10:00:00 GMT"
    final p = s.trim().split(' ');
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final day = int.tryParse(p[1]) ?? 1;
    final month = months[p[2]] ?? 1;
    final year = int.tryParse(p[3]) ?? 2024;
    final t = p.length > 4 ? p[4].split(':') : ['0', '0'];
    return DateTime.utc(
      year,
      month,
      day,
      int.tryParse(t[0]) ?? 0,
      int.tryParse(t.length > 1 ? t[1] : '0') ?? 0,
    ).toLocal();
  }

  static Future<List<StockNews>> _fetchYahooNews(
    String ticker,
    String market,
  ) async {
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

  static _CachedPrice? _kospiNightFuturesCache;

  /// KOSPI 200 야간선물 — KIS API Cloud Function 호출
  static Future<PriceResult?> fetchKospiNightFutures() async {
    final cached = _kospiNightFuturesCache;
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
      return cached.result;
    }

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable(
            'getKospiNightFutures',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 18)),
          );
      final res = await fn.call();
      final d = res.data as Map<String, dynamic>;
      if (d['hasData'] == false) return null;
      final price = (d['price'] as num).toDouble();
      final change = (d['change'] as num).toDouble();
      final changeRate = (d['changeRate'] as num).toDouble();
      final result = PriceResult(
        price: price,
        currency: 'KRW',
        change: change,
        changeRate: changeRate,
      );
      _kospiNightFuturesCache = _CachedPrice(
        result: result,
        fetchedAt: DateTime.now(),
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  static _CachedFearAndGreed? _fearAndGreedCache;
  static const _fearAndGreedCacheDuration = Duration(minutes: 5);

  /// CNN Fear & Greed Index 반환. 실패 시 null. 5분 캐시.
  static Future<FearAndGreedResult?> fetchFearAndGreed() async {
    final cached = _fearAndGreedCache;
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            _fearAndGreedCacheDuration) {
      return cached.result;
    }
    try {
      final uri = Uri.parse(
        'https://production.dataviz.cnn.io/index/fearandgreed/graphdata',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
              'Referer': 'https://www.cnn.com/markets/fear-and-greed',
            },
          )
          .timeout(const Duration(seconds: 8));

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
      _fearAndGreedCache = _CachedFearAndGreed(
        result: result,
        fetchedAt: DateTime.now(),
      );
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
    String ticker,
    String market, {
    double? currentPrice,
  }) async {
    final symbol = toSymbol(ticker, market);

    // 캐시는 가격 변동과 무관한 PER/BPS 기준으로 유지
    // currentPrice가 달라져도 캐시 무효화 안 함 (PER은 서버에서 이미 현재가 반영)
    final cached = _fundamentalsCache[symbol];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            _fundamentalsCacheDuration) {
      // PBR은 현재가로 재계산
      if (currentPrice != null && cached.result.bps != null) {
        return FundamentalsResult(
          per: cached.result.per,
          pbr: currentPrice / cached.result.bps!,
          bps: cached.result.bps,
          marketCap: cached.result.marketCap,
          forwardPer: cached.result.forwardPer,
          sectorAveragePer: cached.result.sectorAveragePer,
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
      _fundamentalsCache[symbol] = _CachedFundamentals(
        result: fundamentals,
        fetchedAt: DateTime.now(),
      );
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
    String ticker,
    double? currentPrice,
  ) async {
    // PER: sise.nhn
    final siseUri = Uri.parse(
      'https://finance.naver.com/item/sise.nhn?code=$ticker',
    );
    final siseRes = await http
        .get(
          siseUri,
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://finance.naver.com',
          },
        )
        .timeout(const Duration(seconds: 8));

    double? per;
    if (siseRes.statusCode == 200) {
      final perMatch = RegExp(
        r'id="_sise_per"[^>]*>\s*([\d.,]+)',
      ).firstMatch(siseRes.body);
      per = double.tryParse(perMatch?.group(1)?.replaceAll(',', '') ?? '');
    }

    // BPS: main.nhn
    double? bps;
    double? pbr;
    int? marketCap;
    double? forwardPer;
    double? sectorAveragePer;
    final mainUri = Uri.parse(
      'https://finance.naver.com/item/main.nhn?code=$ticker',
    );
    final mainRes = await http
        .get(
          mainUri,
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://finance.naver.com',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (mainRes.statusCode == 200) {
      final bpsMatch = RegExp(
        r'BPS\(\uc6d0\)</strong></th>[\s\S]{0,300}<td[^>]*>\s*([\d.,]+)',
      ).firstMatch(mainRes.body);
      bps = double.tryParse(bpsMatch?.group(1)?.replaceAll(',', '') ?? '');
      if (bps != null && currentPrice != null) {
        pbr = currentPrice / bps;
      }
      final capMatch = RegExp(
        r'시가총액</span>[\s\S]{0,500}?<em[^>]*id="_market_sum"[^>]*>\s*([\d,]+)',
      ).firstMatch(mainRes.body);
      final capEok = int.tryParse(
        capMatch?.group(1)?.replaceAll(',', '') ?? '',
      );
      if (capEok != null) {
        marketCap = capEok * 100000000;
      }
    }

    final naverMobile = await _fetchNaverMobileValuation(ticker);
    per ??= naverMobile.per;
    bps ??= naverMobile.bps;
    pbr ??= naverMobile.pbr;
    marketCap ??= naverMobile.marketCap;
    forwardPer = naverMobile.forwardPer;
    sectorAveragePer = naverMobile.sectorAveragePer;
    if (pbr == null && bps != null && currentPrice != null) {
      pbr = currentPrice / bps;
    }

    if (per == null &&
        pbr == null &&
        marketCap == null &&
        forwardPer == null &&
        sectorAveragePer == null) {
      return null;
    }
    return FundamentalsResult(
      per: per,
      pbr: pbr,
      bps: bps,
      marketCap: marketCap,
      forwardPer: forwardPer,
      sectorAveragePer: sectorAveragePer,
    );
  }

  static Future<_NaverMobileValuation> _fetchNaverMobileValuation(
    String ticker,
  ) async {
    try {
      final data = await _fetchNaverMobileIntegration(ticker);
      if (data == null) return const _NaverMobileValuation();
      final totalInfos = data['totalInfos'] as List<dynamic>? ?? const [];
      double? valueByCode(String code) {
        for (final item in totalInfos.whereType<Map>()) {
          if (item['code'] == code) {
            return _parseNaverNumber(item['value']);
          }
        }
        return null;
      }

      final peers = data['industryCompareInfo'] as List<dynamic>? ?? const [];
      final peerPers = await Future.wait(
        peers
            .whereType<Map>()
            .map((p) => (p['itemCode'] as String? ?? '').trim())
            .where((code) => RegExp(r'^\d{6}$').hasMatch(code))
            .take(6)
            .map(_fetchNaverPeerPer),
      );
      final validPeerPers = peerPers
          .whereType<double>()
          .where((v) => v > 0 && v.isFinite)
          .toList();
      final sectorAveragePer = validPeerPers.isEmpty
          ? null
          : validPeerPers.reduce((a, b) => a + b) / validPeerPers.length;

      return _NaverMobileValuation(
        per: valueByCode('per'),
        pbr: valueByCode('pbr'),
        bps: valueByCode('bps'),
        marketCap: _parseNaverMarketCap(totalInfos),
        forwardPer: valueByCode('cnsPer'),
        sectorAveragePer: sectorAveragePer,
      );
    } catch (_) {
      return const _NaverMobileValuation();
    }
  }

  static Future<Map<String, dynamic>?> _fetchNaverMobileIntegration(
    String ticker,
  ) async {
    final uri = Uri.parse(
      'https://m.stock.naver.com/api/stock/$ticker/integration',
    );
    final response = await http
        .get(
          uri,
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://m.stock.naver.com',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Future<double?> _fetchNaverPeerPer(String ticker) async {
    final data = await _fetchNaverMobileIntegration(ticker);
    if (data == null) return null;
    final totalInfos = data['totalInfos'] as List<dynamic>? ?? const [];
    for (final code in const ['cnsPer', 'per']) {
      for (final item in totalInfos.whereType<Map>()) {
        if (item['code'] == code) {
          final value = _parseNaverNumber(item['value']);
          if (value != null && value > 0) return value;
        }
      }
    }
    return null;
  }

  static double? _parseNaverNumber(Object? value) {
    final text = (value?.toString() ?? '').replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
    return double.tryParse(match?.group(0) ?? '');
  }

  static int? _parseNaverMarketCap(List<dynamic> totalInfos) {
    String? raw;
    for (final item in totalInfos.whereType<Map>()) {
      if (item['code'] == 'marketValue') {
        raw = item['value'] as String?;
        break;
      }
    }
    if (raw == null || raw.trim().isEmpty) return null;
    var total = 0.0;
    for (final match in RegExp(r'([\d,]+(?:\.\d+)?)\s*(조|억)').allMatches(raw)) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      if (match.group(2) == '조') total += value * 1000000000000;
      if (match.group(2) == '억') total += value * 100000000;
    }
    return total > 0 ? total.round() : null;
  }

  /// Yahoo Finance quoteSummary (crumb 방식, 미국주식)
  static Future<FundamentalsResult?> _fetchYahooFundamentals(
    String symbol,
  ) async {
    // 크럼이 없으면 발급
    if (_yahoocrumb == null) {
      final cookieRes = await http
          .get(
            Uri.parse('https://fc.yahoo.com'),
            headers: {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 6));
      _yahooCookie = cookieRes.headers['set-cookie']
          ?.split(',')
          .map((c) => c.split(';').first.trim())
          .join('; ');

      final crumbRes = await http
          .get(
            Uri.parse('https://query2.finance.yahoo.com/v1/test/getcrumb'),
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Cookie': _yahooCookie ?? '',
            },
          )
          .timeout(const Duration(seconds: 6));
      _yahoocrumb = crumbRes.body.trim();
    }

    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v10/finance/quoteSummary/$symbol'
      '?modules=summaryDetail,defaultKeyStatistics&crumb=${Uri.encodeComponent(_yahoocrumb!)}',
    );
    final response = await http
        .get(
          uri,
          headers: {'User-Agent': 'Mozilla/5.0', 'Cookie': _yahooCookie ?? ''},
        )
        .timeout(const Duration(seconds: 8));

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

    final per = (result['summaryDetail']?['trailingPE']?['raw'] as num?)
        ?.toDouble();
    final pbr = (result['defaultKeyStatistics']?['priceToBook']?['raw'] as num?)
        ?.toDouble();
    final marketCap = (result['summaryDetail']?['marketCap']?['raw'] as num?)
        ?.toInt();
    final forwardPer =
        (result['summaryDetail']?['forwardPE']?['raw'] as num?)?.toDouble() ??
        (result['defaultKeyStatistics']?['forwardPE']?['raw'] as num?)
            ?.toDouble();

    if (per == null && pbr == null && marketCap == null && forwardPer == null) {
      return null;
    }
    return FundamentalsResult(
      per: per,
      pbr: pbr,
      marketCap: marketCap,
      forwardPer: forwardPer,
    );
  }

  /// 네이버 종목토론방 게시글 (한국주식 전용, 최대 20개)
  static Future<List<DiscussionPost>> fetchDiscussionPosts(
    String ticker,
    String market,
  ) async {
    if (market != 'KS' && market != 'KQ') return [];
    try {
      final uri = Uri.parse(
        'https://finance.naver.com/item/board.nhn?code=$ticker&ordertype=&searchtype=&page=1',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://finance.naver.com',
            },
          )
          .timeout(const Duration(seconds: 8));
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
        posts.add(
          DiscussionPost(
            nid: m.group(2)!,
            title: m.group(3)!,
            date: date,
            viewCount: int.tryParse(m.group(4)!) ?? 0,
            ticker: ticker,
          ),
        );
      }
      return posts;
    } catch (_) {
      return [];
    }
  }

  /// Yahoo Finance 실적 발표 예정일 (US 종목만)
  static Future<DateTime?> fetchEarningsDate(
    String ticker,
    String market,
  ) async {
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
      final dates =
          json['quoteSummary']?['result']?[0]?['calendarEvents']?['earnings']?['earningsDate']
              as List<dynamic>?;
      if (dates == null || dates.isEmpty) return null;
      final raw = dates[0]?['raw'] as int?;
      if (raw == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    } catch (_) {
      return null;
    }
  }

  /// (날짜, 종가) 배열 반환. 실패 시 빈 리스트.
  static Future<List<double>> fetchHistoryByDates(
    String ticker,
    String market,
    DateTime start,
    DateTime end,
  ) async {
    final symbol = toSymbol(ticker, market);
    final days = end.difference(start).inDays;
    final interval = days <= 90
        ? '1d'
        : days <= 730
        ? '1wk'
        : '1mo';
    final period1 = start.millisecondsSinceEpoch ~/ 1000;
    final period2 = end.millisecondsSinceEpoch ~/ 1000;
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&period1=$period1&period2=$period2',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) return [];
      final closes =
          (result['indicators']?['quote']?[0]?['close'] as List<dynamic>?)
              ?.map((v) => v is num ? v.toDouble() : null)
              .toList();
      if (closes == null) return [];
      return closes.whereType<double>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<(DateTime, double)>> fetchHistoryDetailed(
    String ticker,
    String market, {
    String range = '1mo',
    String interval = '1d',
  }) async {
    final symbol = toSymbol(ticker, market);
    try {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body);
      final result = json['chart']?['result']?[0];
      if (result == null) return [];

      final timestamps = (result['timestamp'] as List<dynamic>?)
          ?.whereType<num>()
          .map(
            (v) => DateTime.fromMillisecondsSinceEpoch(
              v.toInt() * 1000,
              isUtc: true,
            ).add(const Duration(hours: 9)),
          )
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
  final DateTime? marketTime;

  const PriceResult({
    required this.price,
    required this.currency,
    required this.change,
    required this.changeRate,
    this.marketTime,
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
  final double? bps; // BPS 캐시용 (PBR 재계산에 사용)
  final int? marketCap;
  final double? forwardPer;
  final double? sectorAveragePer;
  const FundamentalsResult({
    this.per,
    this.pbr,
    this.bps,
    this.marketCap,
    this.forwardPer,
    this.sectorAveragePer,
  });
}

class _NaverMobileValuation {
  final double? per;
  final double? pbr;
  final double? bps;
  final int? marketCap;
  final double? forwardPer;
  final double? sectorAveragePer;

  const _NaverMobileValuation({
    this.per,
    this.pbr,
    this.bps,
    this.marketCap,
    this.forwardPer,
    this.sectorAveragePer,
  });
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

  String get mobileReadUrl =>
      'https://m.stock.naver.com/discussion/domestic/$ticker/posts/$nid';
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

class StockAiAnalysisResult {
  final String companyOverview;
  final String summary;
  final double? score;
  final String scoreLabel;
  final String theme;
  final String sector;
  final String todayReason;
  final String fundamentals;
  final String technical;
  final String news;
  final String momentum;
  final List<String> risks;
  final List<StockAiAnalysisSection> sections;
  final String peerPerAverage;
  final List<String> themePeers;
  final List<StockAiSourceItem> sourceNews;
  final List<StockAiSourceItem> sourceReports;
  final List<StockAiSourceItem> sourceDisclosures;
  final List<StockAiFinancialItem> sourceFinancials;
  final List<StockAiEpsPoint> sourceEpsTimeline;
  final int? sourceMarketCap;
  final double? sourceEps;
  final StockAiInvestorFlow? sourceInvestorFlow;
  final StockAiDailyInvestorFlow? sourceDailyInvestorFlow;
  final List<StockAiCatalyst> catalysts;
  final StockAiValuation? valuation;
  final StockAiTechnicalDetail? technicalDetail;
  final StockAiScenarios? scenarios;
  final List<StockAiRiskDetail> risksDetailed;
  final StockAiTiming? timing;
  final DateTime? generatedAt;

  const StockAiAnalysisResult({
    this.companyOverview = '',
    required this.summary,
    required this.score,
    required this.scoreLabel,
    required this.theme,
    required this.sector,
    required this.todayReason,
    required this.fundamentals,
    required this.technical,
    required this.news,
    required this.momentum,
    required this.risks,
    required this.sections,
    this.peerPerAverage = '',
    this.themePeers = const [],
    this.sourceNews = const [],
    this.sourceReports = const [],
    this.sourceDisclosures = const [],
    this.sourceFinancials = const [],
    this.sourceEpsTimeline = const [],
    this.sourceMarketCap,
    this.sourceEps,
    this.sourceInvestorFlow,
    this.sourceDailyInvestorFlow,
    this.catalysts = const [],
    this.valuation,
    this.technicalDetail,
    this.scenarios,
    this.risksDetailed = const [],
    this.timing,
    required this.generatedAt,
  });

  factory StockAiAnalysisResult.fromMap(Map<String, dynamic> map) {
    String text(String key) => (map[key] as String? ?? '').trim();
    final rawSections = map['sections'] as List<dynamic>? ?? const [];
    final rawThemePeers = map['themePeers'];
    final rawNews = map['sourceNews'] as List<dynamic>? ?? const [];
    final rawReports = map['sourceReports'] as List<dynamic>? ?? const [];
    final rawDisclosures =
        map['sourceDisclosures'] as List<dynamic>? ?? const [];
    final rawFinancials = map['sourceFinancials'] as List<dynamic>? ?? const [];
    final rawEpsTimeline =
        map['sourceEpsTimeline'] as List<dynamic>? ?? const [];
    return StockAiAnalysisResult(
      companyOverview: text('companyOverview'),
      summary: text('summary'),
      score: (map['score'] as num?)?.toDouble(),
      scoreLabel: text('scoreLabel'),
      theme: text('theme'),
      sector: text('sector'),
      todayReason: text('todayReason'),
      fundamentals: text('fundamentals'),
      technical: text('technical'),
      news: text('news'),
      momentum: text('momentum'),
      risks: (map['risks'] as List<dynamic>? ?? const [])
          .map((v) => v.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      peerPerAverage: text('peerPerAverage'),
      themePeers: _parseThemePeers(rawThemePeers),
      sections: rawSections
          .whereType<Map>()
          .map(
            (v) => StockAiAnalysisSection.fromMap(Map<String, dynamic>.from(v)),
          )
          .where((v) => v.title.isNotEmpty && v.body.isNotEmpty)
          .toList(),
      sourceNews: rawNews
          .whereType<Map>()
          .map((v) => StockAiSourceItem.fromMap(Map<String, dynamic>.from(v)))
          .where((v) => v.title.isNotEmpty)
          .toList(),
      sourceReports: rawReports
          .whereType<Map>()
          .map((v) => StockAiSourceItem.fromMap(Map<String, dynamic>.from(v)))
          .where((v) => v.title.isNotEmpty)
          .toList(),
      sourceDisclosures: rawDisclosures
          .whereType<Map>()
          .map((v) => StockAiSourceItem.fromMap(Map<String, dynamic>.from(v)))
          .where((v) => v.title.isNotEmpty)
          .toList(),
      sourceFinancials: rawFinancials
          .whereType<Map>()
          .map(
            (v) => StockAiFinancialItem.fromMap(Map<String, dynamic>.from(v)),
          )
          .where((v) => v.account.isNotEmpty)
          .toList(),
      sourceEpsTimeline: rawEpsTimeline
          .whereType<Map>()
          .map((v) => StockAiEpsPoint.fromMap(Map<String, dynamic>.from(v)))
          .where((v) => v.period.isNotEmpty && v.eps != null)
          .toList(),
      sourceMarketCap: (map['sourceMarketCap'] as num?)?.round(),
      sourceEps: (map['sourceEps'] as num?)?.toDouble(),
      sourceInvestorFlow: map['sourceInvestorFlow'] is Map
          ? StockAiInvestorFlow.fromMap(
              Map<String, dynamic>.from(map['sourceInvestorFlow'] as Map),
            )
          : null,
      sourceDailyInvestorFlow: map['sourceDailyInvestorFlow'] is Map
          ? StockAiDailyInvestorFlow.fromMap(
              Map<String, dynamic>.from(map['sourceDailyInvestorFlow'] as Map),
            )
          : null,
      catalysts: (map['catalysts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((v) => StockAiCatalyst.fromMap(Map<String, dynamic>.from(v)))
          .where((c) => c.title.isNotEmpty)
          .toList(),
      valuation: map['valuation'] is Map
          ? StockAiValuation.fromMap(
              Map<String, dynamic>.from(map['valuation'] as Map),
            )
          : null,
      technicalDetail: map['technicalDetail'] is Map
          ? StockAiTechnicalDetail.fromMap(
              Map<String, dynamic>.from(map['technicalDetail'] as Map),
            )
          : null,
      scenarios: map['scenarios'] is Map
          ? StockAiScenarios.fromMap(
              Map<String, dynamic>.from(map['scenarios'] as Map),
            )
          : null,
      risksDetailed: (map['risksDetailed'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((v) => StockAiRiskDetail.fromMap(Map<String, dynamic>.from(v)))
          .where((r) => r.description.isNotEmpty)
          .toList(),
      timing: map['timing'] is Map
          ? StockAiTiming.fromMap(
              Map<String, dynamic>.from(map['timing'] as Map),
            )
          : null,
      generatedAt: DateTime.tryParse(text('generatedAt')),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'companyOverview': companyOverview,
      'summary': summary,
      'score': score,
      'scoreLabel': scoreLabel,
      'theme': theme,
      'sector': sector,
      'todayReason': todayReason,
      'fundamentals': fundamentals,
      'technical': technical,
      'news': news,
      'momentum': momentum,
      'risks': risks,
      'peerPerAverage': peerPerAverage,
      'themePeers': themePeers,
      'sections': sections.map((section) => section.toMap()).toList(),
      'sourceNews': sourceNews.map((item) => item.toMap()).toList(),
      'sourceReports': sourceReports.map((item) => item.toMap()).toList(),
      'sourceDisclosures': sourceDisclosures
          .map((item) => item.toMap())
          .toList(),
      'sourceFinancials': sourceFinancials.map((item) => item.toMap()).toList(),
      'sourceEpsTimeline': sourceEpsTimeline
          .map((item) => item.toMap())
          .toList(),
      'sourceMarketCap': sourceMarketCap,
      'sourceEps': sourceEps,
      'sourceInvestorFlow': sourceInvestorFlow?.toMap(),
      'sourceDailyInvestorFlow': sourceDailyInvestorFlow?.toMap(),
      'catalysts': catalysts.map((c) => c.toMap()).toList(),
      'valuation': valuation?.toMap(),
      'technicalDetail': technicalDetail?.toMap(),
      'scenarios': scenarios?.toMap(),
      'risksDetailed': risksDetailed.map((r) => r.toMap()).toList(),
      'timing': timing?.toMap(),
      'generatedAt': generatedAt?.toIso8601String(),
    };
  }
}

List<String> _parseThemePeers(dynamic value) {
  final items = <String>[];
  void add(dynamic raw) {
    if (raw == null) return;
    if (raw is Map) {
      add(raw['name'] ?? raw['stockName'] ?? raw['title']);
      return;
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return;
    items.addAll(
      text
          .split(RegExp(r'[,/·\n]'))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty),
    );
  }

  if (value is List) {
    for (final item in value) {
      add(item);
    }
  } else {
    add(value);
  }

  final seen = <String>{};
  return items.where((item) => seen.add(item)).take(8).toList();
}

class StockAiAnalysisSection {
  final String title;
  final String body;

  const StockAiAnalysisSection({required this.title, required this.body});

  factory StockAiAnalysisSection.fromMap(Map<String, dynamic> map) {
    return StockAiAnalysisSection(
      title: (map['title'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'title': title, 'body': body};
  }
}

class StockAiCatalyst {
  final String title;
  final String kind;
  final String impact;
  final String timeline;
  final String confidence;
  final String detail;

  const StockAiCatalyst({
    required this.title,
    required this.kind,
    required this.impact,
    required this.timeline,
    required this.confidence,
    required this.detail,
  });

  factory StockAiCatalyst.fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] as String? ?? '').trim();
    return StockAiCatalyst(
      title: s('title'),
      kind: s('kind'),
      impact: s('impact'),
      timeline: s('timeline'),
      confidence: s('confidence'),
      detail: s('detail'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'kind': kind,
      'impact': impact,
      'timeline': timeline,
      'confidence': confidence,
      'detail': detail,
    };
  }
}

class StockAiPeerComparison {
  final String name;
  final String per;
  final String pbr;

  const StockAiPeerComparison({
    required this.name,
    required this.per,
    required this.pbr,
  });

  factory StockAiPeerComparison.fromMap(Map<String, dynamic> map) {
    return StockAiPeerComparison(
      name: (map['name'] as String? ?? '').trim(),
      per: (map['per'] as String? ?? '').trim(),
      pbr: (map['pbr'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'per': per, 'pbr': pbr};
  }
}

class StockAiValuation {
  final String perVerdict;
  final String pbrVerdict;
  final String forwardPer;
  final String sectorAveragePer;
  final List<StockAiPeerComparison> peerComparison;
  final String reasoning;

  const StockAiValuation({
    required this.perVerdict,
    required this.pbrVerdict,
    required this.forwardPer,
    required this.sectorAveragePer,
    required this.peerComparison,
    required this.reasoning,
  });

  factory StockAiValuation.fromMap(Map<String, dynamic> map) {
    final peers = map['peerComparison'] as List<dynamic>? ?? const [];
    return StockAiValuation(
      perVerdict: (map['perVerdict'] as String? ?? '').trim(),
      pbrVerdict: (map['pbrVerdict'] as String? ?? '').trim(),
      forwardPer: (map['forwardPer'] as String? ?? '').trim(),
      sectorAveragePer: (map['sectorAveragePer'] as String? ?? '').trim(),
      peerComparison: peers
          .whereType<Map>()
          .map(
            (v) => StockAiPeerComparison.fromMap(Map<String, dynamic>.from(v)),
          )
          .where((p) => p.name.isNotEmpty)
          .toList(),
      reasoning: (map['reasoning'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'perVerdict': perVerdict,
      'pbrVerdict': pbrVerdict,
      'forwardPer': forwardPer,
      'sectorAveragePer': sectorAveragePer,
      'peerComparison': peerComparison.map((p) => p.toMap()).toList(),
      'reasoning': reasoning,
    };
  }
}

class StockAiTechnicalDetail {
  final String maPosition;
  final String rsiVerdict;
  final String bollingerVerdict;
  final String support;
  final String resistance;
  final String pattern;
  final String reasoning;

  const StockAiTechnicalDetail({
    required this.maPosition,
    required this.rsiVerdict,
    required this.bollingerVerdict,
    required this.support,
    required this.resistance,
    required this.pattern,
    required this.reasoning,
  });

  factory StockAiTechnicalDetail.fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] as String? ?? '').trim();
    return StockAiTechnicalDetail(
      maPosition: s('maPosition'),
      rsiVerdict: s('rsiVerdict'),
      bollingerVerdict: s('bollingerVerdict'),
      support: s('support'),
      resistance: s('resistance'),
      pattern: s('pattern'),
      reasoning: s('reasoning'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'maPosition': maPosition,
      'rsiVerdict': rsiVerdict,
      'bollingerVerdict': bollingerVerdict,
      'support': support,
      'resistance': resistance,
      'pattern': pattern,
      'reasoning': reasoning,
    };
  }
}

class StockAiScenario {
  final String trigger;
  final String priceTarget;
  final double? probability;
  final String narrative;

  const StockAiScenario({
    required this.trigger,
    required this.priceTarget,
    required this.probability,
    required this.narrative,
  });

  factory StockAiScenario.fromMap(Map<String, dynamic> map) {
    return StockAiScenario(
      trigger: (map['trigger'] as String? ?? '').trim(),
      priceTarget: (map['priceTarget'] as String? ?? '').trim(),
      probability: (map['probability'] as num?)?.toDouble(),
      narrative: (map['narrative'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trigger': trigger,
      'priceTarget': priceTarget,
      'probability': probability,
      'narrative': narrative,
    };
  }
}

class StockAiScenarios {
  final StockAiScenario? bull;
  final StockAiScenario? base;
  final StockAiScenario? bear;

  const StockAiScenarios({
    required this.bull,
    required this.base,
    required this.bear,
  });

  factory StockAiScenarios.fromMap(Map<String, dynamic> map) {
    StockAiScenario? read(String key) {
      final raw = map[key];
      if (raw is! Map) return null;
      return StockAiScenario.fromMap(Map<String, dynamic>.from(raw));
    }

    return StockAiScenarios(
      bull: read('bull'),
      base: read('base'),
      bear: read('bear'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bull': bull?.toMap(),
      'base': base?.toMap(),
      'bear': bear?.toMap(),
    };
  }
}

class StockAiRiskDetail {
  final String category;
  final String severity;
  final String probability;
  final String description;
  final String mitigant;

  const StockAiRiskDetail({
    required this.category,
    required this.severity,
    required this.probability,
    required this.description,
    required this.mitigant,
  });

  factory StockAiRiskDetail.fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] as String? ?? '').trim();
    return StockAiRiskDetail(
      category: s('category'),
      severity: s('severity'),
      probability: s('probability'),
      description: s('description'),
      mitigant: s('mitigant'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'severity': severity,
      'probability': probability,
      'description': description,
      'mitigant': mitigant,
    };
  }
}

class StockAiTiming {
  final String shortTerm;
  final String midTerm;
  final String action;
  final String actionReason;

  const StockAiTiming({
    required this.shortTerm,
    required this.midTerm,
    required this.action,
    required this.actionReason,
  });

  factory StockAiTiming.fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] as String? ?? '').trim();
    return StockAiTiming(
      shortTerm: s('shortTerm'),
      midTerm: s('midTerm'),
      action: s('action'),
      actionReason: s('actionReason'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shortTerm': shortTerm,
      'midTerm': midTerm,
      'action': action,
      'actionReason': actionReason,
    };
  }
}

class StockAiSourceItem {
  final String title;
  final String url;
  final String publisher;
  final String publishedAt;
  final String date;
  final String submitter;
  final String receiptNo;
  final String opinion;
  final double? targetPrice;
  final double? previousTargetPrice;
  final double? priceAtWriteDate;

  const StockAiSourceItem({
    required this.title,
    this.url = '',
    this.publisher = '',
    this.publishedAt = '',
    this.date = '',
    this.submitter = '',
    this.receiptNo = '',
    this.opinion = '',
    this.targetPrice,
    this.previousTargetPrice,
    this.priceAtWriteDate,
  });

  factory StockAiSourceItem.fromMap(Map<String, dynamic> map) {
    return StockAiSourceItem(
      title: (map['title'] as String? ?? '').trim(),
      url: (map['url'] as String? ?? '').trim(),
      publisher: (map['publisher'] as String? ?? '').trim(),
      publishedAt: (map['publishedAt'] as String? ?? '').trim(),
      date: (map['date'] as String? ?? '').trim(),
      submitter: (map['submitter'] as String? ?? '').trim(),
      receiptNo: (map['receiptNo'] as String? ?? '').trim(),
      opinion: (map['opinion'] as String? ?? '').trim(),
      targetPrice: (map['targetPrice'] as num?)?.toDouble(),
      previousTargetPrice: (map['previousTargetPrice'] as num?)?.toDouble(),
      priceAtWriteDate: (map['priceAtWriteDate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'url': url,
      'publisher': publisher,
      'publishedAt': publishedAt,
      'date': date,
      'submitter': submitter,
      'receiptNo': receiptNo,
      'opinion': opinion,
      'targetPrice': targetPrice,
      'previousTargetPrice': previousTargetPrice,
      'priceAtWriteDate': priceAtWriteDate,
    };
  }
}

class StockAiFinancialItem {
  final String account;
  final String current;
  final String previous;
  final String statement;

  const StockAiFinancialItem({
    required this.account,
    this.current = '',
    this.previous = '',
    this.statement = '',
  });

  factory StockAiFinancialItem.fromMap(Map<String, dynamic> map) {
    return StockAiFinancialItem(
      account: (map['account'] as String? ?? '').trim(),
      current: (map['current'] as String? ?? '').trim(),
      previous: (map['previous'] as String? ?? '').trim(),
      statement: (map['statement'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'account': account,
      'current': current,
      'previous': previous,
      'statement': statement,
    };
  }
}

class StockAiEpsPoint {
  final String period;
  final double? eps;
  final double? per;
  final bool estimate;

  const StockAiEpsPoint({
    required this.period,
    required this.eps,
    this.per,
    this.estimate = false,
  });

  factory StockAiEpsPoint.fromMap(Map<String, dynamic> map) {
    return StockAiEpsPoint(
      period: (map['period'] as String? ?? '').trim(),
      eps: (map['eps'] as num?)?.toDouble(),
      per: (map['per'] as num?)?.toDouble(),
      estimate: map['estimate'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'period': period,
      'eps': eps,
      'per': per,
      'estimate': estimate,
    };
  }
}

class StockAiInvestorFlow {
  final String marketDate;
  final String market;
  final StockAiInvestorFlowItem? foreign;
  final StockAiInvestorFlowItem? institution;

  const StockAiInvestorFlow({
    this.marketDate = '',
    this.market = '',
    this.foreign,
    this.institution,
  });

  factory StockAiInvestorFlow.fromMap(Map<String, dynamic> map) {
    return StockAiInvestorFlow(
      marketDate: (map['marketDate'] as String? ?? '').trim(),
      market: (map['market'] as String? ?? '').trim(),
      foreign: map['foreign'] is Map
          ? StockAiInvestorFlowItem.fromMap(
              Map<String, dynamic>.from(map['foreign'] as Map),
            )
          : null,
      institution: map['institution'] is Map
          ? StockAiInvestorFlowItem.fromMap(
              Map<String, dynamic>.from(map['institution'] as Map),
            )
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'marketDate': marketDate,
      'market': market,
      'foreign': foreign?.toMap(),
      'institution': institution?.toMap(),
    };
  }
}

class StockAiInvestorFlowItem {
  final int? rank;
  final String amountText;
  final String quantityText;

  const StockAiInvestorFlowItem({
    this.rank,
    this.amountText = '',
    this.quantityText = '',
  });

  factory StockAiInvestorFlowItem.fromMap(Map<String, dynamic> map) {
    return StockAiInvestorFlowItem(
      rank: (map['rank'] as num?)?.round(),
      amountText: (map['amountText'] as String? ?? '').trim(),
      quantityText: (map['quantityText'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rank': rank,
      'amountText': amountText,
      'quantityText': quantityText,
    };
  }
}

class StockAiDailyInvestorFlow {
  final List<StockAiInvestorFlowDay> days;
  final double? foreignNet14;
  final double? institutionNet14;
  final double? latestForeignHoldRate;

  const StockAiDailyInvestorFlow({
    this.days = const [],
    this.foreignNet14,
    this.institutionNet14,
    this.latestForeignHoldRate,
  });

  factory StockAiDailyInvestorFlow.fromMap(Map<String, dynamic> map) {
    final rawDays = map['days'] as List<dynamic>? ?? const [];
    return StockAiDailyInvestorFlow(
      days: rawDays
          .whereType<Map>()
          .map(
            (v) => StockAiInvestorFlowDay.fromMap(Map<String, dynamic>.from(v)),
          )
          .toList(),
      foreignNet14: (map['foreignNet14'] as num?)?.toDouble(),
      institutionNet14: (map['institutionNet14'] as num?)?.toDouble(),
      latestForeignHoldRate: (map['latestForeignHoldRate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'days': days.map((day) => day.toMap()).toList(),
      'foreignNet14': foreignNet14,
      'institutionNet14': institutionNet14,
      'latestForeignHoldRate': latestForeignHoldRate,
    };
  }
}

class StockAiInvestorFlowDay {
  final String date;
  final double? close;
  final double? changeRate;
  final double? volume;
  final double? foreignNet;
  final double? institutionNet;
  final double? foreignHoldRate;

  const StockAiInvestorFlowDay({
    this.date = '',
    this.close,
    this.changeRate,
    this.volume,
    this.foreignNet,
    this.institutionNet,
    this.foreignHoldRate,
  });

  factory StockAiInvestorFlowDay.fromMap(Map<String, dynamic> map) {
    return StockAiInvestorFlowDay(
      date: (map['date'] as String? ?? '').trim(),
      close: (map['close'] as num?)?.toDouble(),
      changeRate: (map['changeRate'] as num?)?.toDouble(),
      volume: (map['volume'] as num?)?.toDouble(),
      foreignNet: (map['foreignNet'] as num?)?.toDouble(),
      institutionNet: (map['institutionNet'] as num?)?.toDouble(),
      foreignHoldRate: (map['foreignHoldRate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'close': close,
      'changeRate': changeRate,
      'volume': volume,
      'foreignNet': foreignNet,
      'institutionNet': institutionNet,
      'foreignHoldRate': foreignHoldRate,
    };
  }
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
