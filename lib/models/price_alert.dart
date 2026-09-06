import 'package:cloud_firestore/cloud_firestore.dart';

/// 조건 알림 유형.
/// - priceAbove / priceBelow: 목표가 도달 (value = 목표 가격)
/// - changeUp / changeDown: 당일 등락률 도달 (value = 퍼센트, 절댓값)
enum AlertType { priceAbove, priceBelow, changeUp, changeDown }

extension AlertTypeX on AlertType {
  String get wire => switch (this) {
    AlertType.priceAbove => 'price_above',
    AlertType.priceBelow => 'price_below',
    AlertType.changeUp => 'change_up',
    AlertType.changeDown => 'change_down',
  };

  bool get isPrice =>
      this == AlertType.priceAbove || this == AlertType.priceBelow;

  static AlertType fromWire(String? s) => switch (s) {
    'price_above' => AlertType.priceAbove,
    'price_below' => AlertType.priceBelow,
    'change_up' => AlertType.changeUp,
    'change_down' => AlertType.changeDown,
    _ => AlertType.priceAbove,
  };
}

class PriceAlert {
  final String id;
  final String uid;
  final String ticker;
  final String name;
  final String market; // KS, KQ, US
  final AlertType type;
  final double value;
  final bool enabled;
  final bool triggered;
  final DateTime? createdAt;
  final DateTime? triggeredAt;

  const PriceAlert({
    required this.id,
    required this.uid,
    required this.ticker,
    required this.name,
    required this.market,
    required this.type,
    required this.value,
    this.enabled = true,
    this.triggered = false,
    this.createdAt,
    this.triggeredAt,
  });

  factory PriceAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PriceAlert(
      id: doc.id,
      uid: (d['uid'] as String?) ?? '',
      ticker: (d['ticker'] as String?) ?? '',
      name: (d['name'] as String?) ?? '',
      market: (d['market'] as String?) ?? 'KS',
      type: AlertTypeX.fromWire(d['type'] as String?),
      value: (d['value'] as num?)?.toDouble() ?? 0,
      enabled: (d['enabled'] as bool?) ?? true,
      triggered: (d['triggered'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      triggeredAt: (d['triggeredAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'ticker': ticker,
    'name': name,
    'market': market,
    'type': type.wire,
    'value': value,
    'enabled': enabled,
    'triggered': triggered,
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// "삼성전자 ₩80,000 도달" 같은 사람이 읽는 조건 라벨.
  String describe() {
    final v = _formatValue();
    return switch (type) {
      AlertType.priceAbove => '$v 이상 도달 시',
      AlertType.priceBelow => '$v 이하 도달 시',
      AlertType.changeUp => '당일 +$v% 이상 상승 시',
      AlertType.changeDown => '당일 -$v% 이상 하락 시',
    };
  }

  String _formatValue() {
    if (!type.isPrice) return value.toStringAsFixed(1);
    if (market == 'US') return '\$${value.toStringAsFixed(2)}';
    return '₩${_thousands(value)}';
  }

  static String _thousands(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
