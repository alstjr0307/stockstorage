import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/stock_price_service.dart';

class StockSearchField extends StatefulWidget {
  final String initialTicker;
  final String initialName;
  final void Function(String ticker, String name, String market) onSelected;

  const StockSearchField({
    super.key,
    required this.initialTicker,
    required this.initialName,
    required this.onSelected,
  });

  @override
  State<StockSearchField> createState() => _StockSearchFieldState();
}

class _StockSearchFieldState extends State<StockSearchField> {
  late final TextEditingController _searchController;
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<StockSearchResult> _results = [];
  Timer? _debounce;
  bool _loading = false;
  bool _selected = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTicker.isNotEmpty
        ? '${widget.initialTicker}  ${widget.initialName}'
        : '';
    _searchController = TextEditingController(text: initial);
    if (widget.initialTicker.isNotEmpty) _selected = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _selected = false;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _removeOverlay();
      return;
    }
    _debounce = Timer(
        const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await StockPriceService.searchStocks(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
    if (results.isNotEmpty) _showOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(builder: (_) => _buildDropdown());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _onSelect(StockSearchResult r) {
    _selected = true;
    _searchController.text = '${r.ticker}  ${r.name}';
    _removeOverlay();
    widget.onSelected(r.ticker, r.name, r.market);
  }

  Widget _buildDropdown() {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2A40) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Positioned(
      width: 300,
      child: CompositedTransformFollower(
        link: _layerLink,
        offset: const Offset(0, 56),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16)
              ],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final marketColor = switch (r.market) {
                  'KS' => Colors.blueAccent,
                  'KQ' => Colors.purpleAccent,
                  _ => Colors.orangeAccent,
                };
                final marketLabel = switch (r.market) {
                  'KS' => 'KOSPI',
                  'KQ' => 'KOSDAQ',
                  _ => 'US',
                };
                return InkWell(
                  onTap: () => _onSelect(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: marketColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(marketLabel,
                              style: GoogleFonts.inter(
                                  color: marketColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  style: GoogleFonts.inter(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(r.ticker,
                                  style: GoogleFonts.robotoMono(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _searchController,
        style: GoogleFonts.inter(color: cs.onSurface),
        onChanged: _onChanged,
        onTap: () {
          if (!_selected && _searchController.text.isNotEmpty) {
            _search(_searchController.text.trim());
          }
        },
        decoration: InputDecoration(
          hintText: '종목명 또는 티커 검색 (예: 삼성전자, AAPL)',
          hintStyle: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.28), fontSize: 13),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF4ADE80))),
                )
              : _selected
                  ? const Icon(Icons.check_circle,
                      color: Color(0xFF4ADE80), size: 18)
                  : Icon(Icons.search,
                      color: cs.onSurface.withValues(alpha: 0.3), size: 18),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        validator: (_) => !_selected ? '종목을 검색하여 선택하세요' : null,
      ),
    );
  }
}
