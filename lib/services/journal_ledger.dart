import '../models/trading_journal.dart';

enum JournalBuyKind { first, averageDown, averageUp, samePrice, sell, note }

extension JournalBuyKindLabel on JournalBuyKind {
  String get label => switch (this) {
    JournalBuyKind.first => '첫 매수',
    JournalBuyKind.averageDown => '추가매수',
    JournalBuyKind.averageUp => '추가매수',
    JournalBuyKind.samePrice => '추가매수',
    JournalBuyKind.sell => '매도',
    JournalBuyKind.note => '메모',
  };
}

class JournalEffect {
  const JournalEffect({
    required this.trade,
    required this.kind,
    required this.beforeQuantity,
    required this.afterQuantity,
    required this.beforeAverage,
    required this.afterAverage,
    required this.realized,
    required this.buyNumber,
    this.issue,
  });
  final TradingJournal trade;
  final JournalBuyKind kind;
  final double beforeQuantity, afterQuantity, beforeAverage, afterAverage;
  final double realized;
  final int buyNumber;
  final String? issue;
}

class JournalPosition {
  const JournalPosition({
    required this.key,
    required this.events,
    required this.quantity,
    required this.cost,
    required this.realized,
    required this.soldCost,
    required this.hasOrderAmbiguity,
  });
  final String key;
  final List<JournalEffect> events;
  final double quantity, cost, realized, soldCost;
  final bool hasOrderAmbiguity;
  bool get reliable =>
      !hasOrderAmbiguity && events.every((e) => e.issue == null);
  double get average => quantity > JournalLedger.epsilon ? cost / quantity : 0;
  double? get realizedRate =>
      reliable && soldCost > 0 ? realized / soldCost * 100 : null;
  TradingJournal get stock => events.last.trade;
  JournalEffect? effectFor(String id) =>
      reliable ? events.where((e) => e.trade.id == id).firstOrNull : null;
}

/// Read-only projection. Never changes saved buyPrice, linkedBuyId or dates.
/// All costs and profits are in the stock's native currency, before fees/tax.
class JournalLedger {
  static const epsilon = 1e-10;
  static JournalPosition? forStock(
    Iterable<TradingJournal> journals,
    TradingJournal stock,
  ) {
    final unique = <String, TradingJournal>{
      for (final j in journals.where((j) => stockKey(j) == stockKey(stock)))
        j.id: j,
    };
    return project(unique.values).firstOrNull;
  }

  static String stockKey(TradingJournal j) =>
      '${j.uid}|${j.market.trim().toUpperCase()}|${j.ticker.trim().isEmpty ? 'name:${j.stockName.trim()}' : j.ticker.trim().toUpperCase()}';

  static int compare(TradingJournal a, TradingJournal b) {
    final trade = tradeDay(a).compareTo(tradeDay(b));
    if (trade != 0) return trade;
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  }

  static DateTime tradeDay(TradingJournal j) =>
      DateTime(j.tradeDate.year, j.tradeDate.month, j.tradeDate.day);

  // Only an identical input timestamp is unresolved. Firestore document IDs
  // stabilize display order but must not pretend to encode input order.
  static String _orderKey(TradingJournal j) =>
      '${tradeDay(j).millisecondsSinceEpoch}:${j.createdAt.microsecondsSinceEpoch}';

  static List<JournalPosition> project(Iterable<TradingJournal> journals) {
    final groups = <String, List<TradingJournal>>{};
    for (final j in journals) {
      groups.putIfAbsent(stockKey(j), () => []).add(j);
    }
    return groups.entries.map((g) => _position(g.key, g.value)).toList()
      ..sort((a, b) => compare(b.stock, a.stock));
  }

  static JournalPosition _position(String key, List<TradingJournal> input) {
    final trades = [...input]..sort(compare);
    final timeCounts = <String, int>{};
    for (final t in trades.where((t) => t.action == '매수' || t.action == '매도')) {
      timeCounts.update(_orderKey(t), (n) => n + 1, ifAbsent: () => 1);
    }
    var quantity = 0.0, cost = 0.0, realized = 0.0, soldCost = 0.0;
    var number = 0;
    final effects = <JournalEffect>[];
    for (final t in trades) {
      final beforeQty = quantity;
      final beforeAvg = quantity > epsilon ? cost / quantity : 0.0;
      var profit = 0.0;
      String? issue;
      var kind = JournalBuyKind.note;
      final financial = t.action == '매수' || t.action == '매도';
      if (financial &&
          (!t.price.isFinite ||
              !t.quantity.isFinite ||
              t.price <= 0 ||
              t.quantity <= 0 ||
              !(t.price * t.quantity).isFinite ||
              (t.action == '매수' &&
                  (!(cost + t.price * t.quantity).isFinite ||
                      !(quantity + t.quantity).isFinite)))) {
        issue = '가격·수량 확인 필요';
      } else if (t.action == '매수') {
        if (quantity <= epsilon) {
          number = 0;
          kind = JournalBuyKind.first;
        } else {
          final difference = t.price - beforeAvg;
          final tolerance = beforeAvg.abs() * 1e-10 + 1e-8;
          kind = difference.abs() <= tolerance
              ? JournalBuyKind.samePrice
              : difference < 0
              ? JournalBuyKind.averageDown
              : JournalBuyKind.averageUp;
        }
        number++;
        quantity += t.quantity;
        cost += t.price * t.quantity;
      } else if (t.action == '매도') {
        kind = JournalBuyKind.sell;
        if (t.quantity > quantity + epsilon || quantity <= epsilon) {
          issue = '거래 당시 보유수량 초과';
        } else {
          // Only tolerate numerical residue, never silently absorb an oversell.
          final sold = t.quantity > quantity ? quantity : t.quantity;
          final basis = beforeAvg * sold;
          profit = t.price * sold - basis;
          quantity -= sold;
          cost -= basis;
          realized += profit;
          soldCost += basis;
          if (quantity.abs() <= epsilon) {
            quantity = 0;
            cost = 0;
          }
        }
      }
      if (financial && (timeCounts[_orderKey(t)] ?? 0) > 1) {
        issue ??= '입력 시각이 같은 거래의 순서 확인 필요';
      }
      effects.add(
        JournalEffect(
          trade: t,
          kind: kind,
          beforeQuantity: beforeQty,
          afterQuantity: quantity,
          beforeAverage: beforeAvg,
          afterAverage: quantity > epsilon ? cost / quantity : 0,
          realized: profit,
          buyNumber: number,
          issue: issue,
        ),
      );
    }
    return JournalPosition(
      key: key,
      events: List.unmodifiable(effects),
      quantity: quantity,
      cost: cost,
      realized: realized,
      soldCost: soldCost,
      hasOrderAmbiguity: timeCounts.values.any((n) => n > 1),
    );
  }

  static bool sameFinancialRecord(TradingJournal a, TradingJournal b) =>
      stockKey(a) == stockKey(b) &&
      a.action == b.action &&
      a.price == b.price &&
      a.quantity == b.quantity &&
      a.tradeDate == b.tradeDate &&
      a.createdAt == b.createdAt;

  /// Validate the entire affected history, including sales AFTER a backdated
  /// insertion/edit/deletion. Unrelated legacy problems don't block this stock.
  static String? validateMutation(
    List<TradingJournal> before, {
    TradingJournal? next,
    String? deleteId,
  }) {
    final id = next?.id ?? deleteId;
    TradingJournal? old;
    for (final j in before) {
      if (j.id == id) {
        old = j;
        break;
      }
    }
    if (next != null && old != null && sameFinancialRecord(old, next)) {
      return null;
    }
    final affected = {
      if (old != null) stockKey(old),
      if (next != null) stockKey(next),
    };
    final after = before.where((j) => j.id != id).toList();
    if (next != null) after.add(next);
    for (final p in project(
      after.where((j) => affected.contains(stockKey(j))),
    )) {
      if (!p.reliable) {
        final issue = p.events.firstWhere((e) => e.issue != null);
        return '${issue.trade.stockName}: ${issue.issue}. 거래 날짜·시각과 수량을 확인해주세요.';
      }
    }
    return null;
  }
}
