/// Public stock identity only; never includes a user's private analysis or UID.
class SharedStockLink {
  const SharedStockLink({
    required this.market,
    required this.ticker,
    this.name = '',
  });

  final String market;
  final String ticker;
  final String name;
  static const host = 'stockstorage-13828.web.app';

  static bool isValid(String market, String ticker) =>
      const ['KS', 'KQ', 'US'].contains(market) &&
      (market == 'US'
          ? RegExp(r'^[A-Z][A-Z0-9.\-]{0,14}$').hasMatch(ticker)
          : RegExp(r'^\d{6}$').hasMatch(ticker));

  Uri toUri({String source = 'stock_share'}) => Uri.https(
    host,
    '/stock/${market.toUpperCase()}/${ticker.toUpperCase()}',
    {
      if (name.trim().isNotEmpty) 'name': name.trim(),
      'utm_source': source,
      'utm_medium': 'share',
      'utm_campaign': 'stock_follow',
    },
  );

  static SharedStockLink? parse(Uri uri, {bool webEntry = false}) {
    if (uri.scheme != 'https' ||
        uri.host != (webEntry ? 'stockstorage-web.web.app' : host)) {
      return null;
    }
    final parts = uri.pathSegments;
    final market = webEntry
        ? uri.queryParameters['market']
        : (parts.length == 3 && parts[0] == 'stock' ? parts[1] : null);
    final ticker = webEntry
        ? uri.queryParameters['ticker']
        : (parts.length == 3 && parts[0] == 'stock' ? parts[2] : null);
    if (market == null || ticker == null || !isValid(market, ticker)) {
      return null;
    }
    final name = (uri.queryParameters['name'] ?? '').trim();
    return SharedStockLink(
      market: market,
      ticker: ticker,
      name: name.length <= 80 ? name : ticker,
    );
  }
}
