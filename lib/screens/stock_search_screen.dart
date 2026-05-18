import 'dart:async';

import 'package:flutter/material.dart';

import '../services/stock_price_service.dart';
import 'stock_detail_screen.dart';

class StockSearchScreen extends StatefulWidget {
  const StockSearchScreen({super.key});

  @override
  State<StockSearchScreen> createState() => _StockSearchScreenState();
}

class _StockSearchScreenState extends State<StockSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<StockSearchResult> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    final results = await StockPriceService.searchStocks(query);
    if (!mounted || _controller.text.trim() != query) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _openResult(StockSearchResult result) {
    Navigator.push(
      context,
      stockDetailRoute(
        stockPickFromSearchResult(result),
        enablePickFeatures: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('종목 검색'), centerTitle: false),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _controller,
                autoFocus: true,
                hintText: '종목명 또는 티커를 검색하세요',
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
                onChanged: _onChanged,
                onSubmitted: (value) => _search(value.trim()),
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(
              child: _results.isEmpty
                  ? _SearchEmptyState(query: _lastQuery, loading: _loading)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: cs.onSurface.withValues(alpha: 0.08),
                      ),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return ListTile(
                          onTap: () => _openResult(item),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: cs.primary.withValues(alpha: 0.12),
                            child: Text(
                              item.market,
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text('${item.ticker} · ${item.exchange}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query, required this.loading});

  final String query;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = query.isEmpty
        ? '검색어를 입력하면 종목을 찾을 수 있습니다.'
        : loading
        ? '검색 중입니다.'
        : '검색 결과가 없습니다.';
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.48),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
