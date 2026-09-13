import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/index_detail_screen.dart';
import '../services/stock_price_service.dart';

class WebIndicesPage extends StatefulWidget {
  const WebIndicesPage({
    super.key,
    this.fetchPrice = StockPriceService.fetchPrice,
  });

  final Future<PriceResult?> Function(String ticker, String market) fetchPrice;

  static const entries = <(String, String)>[
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('나스닥100 선물', 'NQ=F'),
    ('S&P500', '^GSPC'),
    ('나스닥 종합', '^IXIC'),
    ('달러/원', 'KRW=X'),
  ];

  @override
  State<WebIndicesPage> createState() => _WebIndicesPageState();
}

class _WebIndicesPageState extends State<WebIndicesPage> {
  final _quotes = <String, PriceResult?>{};
  final _pending = <String>{};
  Future<void>? _refreshing;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() => _refreshing ??= _loadAll().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _loadAll() async {
    setState(() => _pending.addAll(WebIndicesPage.entries.map((e) => e.$2)));
    await Future.wait(
      WebIndicesPage.entries.map((entry) async {
        final symbol = entry.$2;
        StockPriceService.invalidateCache(symbol);
        PriceResult? result;
        try {
          result = await widget.fetchPrice(symbol, 'US');
        } catch (_) {
          // A failed quote must not prevent the other indices from appearing.
        }
        if (!mounted) return;
        setState(() {
          _quotes[symbol] = result;
          _pending.remove(symbol);
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 지수'),
        actions: [
          IconButton(
            tooltip: '시세 새로고침',
            onPressed: _pending.isEmpty ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '새로고침으로 시세를 갱신할 수 있어요. 항목을 누르면 차트를 볼 수 있어요.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final (name, symbol) in WebIndicesPage.entries)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildQuote(symbol, cs),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          IndexDetailScreen(name: name, symbol: symbol),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuote(String symbol, ColorScheme cs) {
    if (_pending.contains(symbol)) {
      return const Text('시세 불러오는 중…');
    }
    final quote = _quotes[symbol];
    if (quote == null) {
      return Text(
        '시세를 불러오지 못했어요. 새로고침해 주세요.',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    }
    final sign = quote.changeRate > 0 ? '+' : '';
    final color = quote.changeRate > 0
        ? const Color(0xFFE64960)
        : quote.changeRate < 0
        ? const Color(0xFF3182F6)
        : cs.onSurfaceVariant;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          NumberFormat('#,##0.00').format(quote.price),
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '$sign${quote.changeRate.toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
