import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../models/price_alert.dart';
import '../models/stock_pick.dart';
import '../screens/subscription_screen.dart';
import '../services/firestore_service.dart';
import '../services/analytics_service.dart';
import '../services/subscription_service.dart';

const _alertAccent = Color(0xFF10B981);

/// 조건 알림 추가 바텀시트를 띄운다. 프리미엄 게이팅(무료 활성 1개)을 포함한다.
/// 종목 상세의 [PriceAlertSection] 밖(관심종목 목록 등)에서도 쓰는 공개 진입점.
/// 실제로 알림이 추가되면 true.
Future<bool> showAddPriceAlertSheet(
  BuildContext context, {
  required StockPick pick,
  double? currentPrice,
  String source = 'stock_detail',
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('로그인하면 조건 알림을 설정할 수 있어요')));
    return false;
  }
  final fs = FirestoreService();
  AnalyticsService.instance.logStockJourney(
    'price_alert_start',
    ticker: pick.ticker,
    market: pick.market,
    source: source,
  );
  // 무료 유저는 활성 알림 1개까지
  if (!SubscriptionService.instance.isPremium) {
    final count = await fs.activeAlertCount(uid);
    if (count >= FirestoreService.freeAlertLimit) {
      if (context.mounted) {
        if (kIsWeb) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('무료 알림 한도에 도달했어요. 기존 알림을 정리하거나 앱에서 구독을 확인해주세요.'),
            ),
          );
        } else {
          _showPremiumUpsell(context);
        }
      }
      return false;
    }
  }
  if (!context.mounted) return false;
  final result = await showModalBottomSheet<PriceAlert>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AlertEditorSheet(pick: pick, currentPrice: currentPrice),
  );
  if (result == null) return false;
  await fs.addPriceAlert(result);
  AnalyticsService.instance.logStockJourney(
    'price_alert_created',
    ticker: pick.ticker,
    market: pick.market,
    source: source,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('조건 알림을 설정했어요 🔔')));
  }
  return true;
}

/// 한 종목에 걸린 조건 알림을 보고 추가·삭제하는 바텀시트.
/// 관심종목 목록의 벨 버튼에서 사용한다.
Future<void> showStockPriceAlertsSheet(
  BuildContext context, {
  required StockPick pick,
  double? currentPrice,
}) async {
  // 시트 안에서 곧바로 다른 시트를 띄우면 컨텍스트가 꼬이므로,
  // '추가'를 누르면 true 로 pop 한 뒤 바깥에서 에디터를 연다.
  final wantsAdd = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _StockAlertsSheet(pick: pick),
  );
  if (wantsAdd == true && context.mounted) {
    await showAddPriceAlertSheet(
      context,
      pick: pick,
      currentPrice: currentPrice,
    );
  }
}

void _showPremiumUpsell(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: Color(0xFFF5C451)),
          SizedBox(width: 8),
          Text('프리미엄 전용', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      content: Text(
        '무료 플랜은 조건 알림을 1개까지 설정할 수 있어요.\n'
        '프리미엄으로 업그레이드하면 종목마다 여러 개의 목표가·등락률 알림을 '
        '무제한으로 걸어둘 수 있습니다.',
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.78),
          fontSize: 13.5,
          height: 1.6,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            '닫기',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _alertAccent),
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            );
          },
          child: const Text(
            '프리미엄 보기',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

/// 종목 상세에 표시되는 조건 알림 섹션.
/// 목표가/등락률 조건을 걸어두면 서버가 감지해 FCM 푸시를 보낸다.
/// 무료 유저는 활성 알림 1개, 프리미엄은 무제한.
class PriceAlertSection extends StatelessWidget {
  const PriceAlertSection({
    super.key,
    required this.pick,
    required this.currentPrice,
  });

  final StockPick pick;
  final double? currentPrice;

  static const _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final fs = FirestoreService();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                size: 18,
                color: _accent,
              ),
              const SizedBox(width: 7),
              Text(
                '조건 알림',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              _PremiumTag(),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '목표가·등락률에 도달하면 푸시로 알려드려요',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 12),
          if (user == null)
            _hint(cs, '로그인하면 조건 알림을 설정할 수 있어요')
          else
            StreamBuilder<List<PriceAlert>>(
              stream: fs.watchPriceAlertsForStock(
                user.uid,
                pick.ticker,
                pick.market,
              ),
              builder: (context, snapshot) {
                final alerts = snapshot.data ?? const <PriceAlert>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final a in alerts) ...[
                      _AlertRow(alert: a, fs: fs),
                      const SizedBox(height: 8),
                    ],
                    _AddButton(
                      onTap: () => showAddPriceAlertSheet(
                        context,
                        pick: pick,
                        currentPrice: currentPrice,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _hint(ColorScheme cs, String text) => Text(
    text,
    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45), fontSize: 13),
  );
}

class _PremiumTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (SubscriptionService.instance.isPremium) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C451).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '무료 1개',
        style: TextStyle(
          color: Color(0xFFCF9F2E),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18, color: cs.onSurface),
            const SizedBox(width: 4),
            Text(
              '조건 알림 추가',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.fs});
  final PriceAlert alert;
  final FirestoreService fs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fired = alert.triggered;
    final accent = fired
        ? cs.onSurface.withValues(alpha: 0.4)
        : const Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.describe(),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: fired ? 0.5 : 0.9),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    decoration: fired ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (fired)
                  Text(
                    '발동됨 · 다시 켜려면 눌러주세요',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (fired)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: const Color(0xFF10B981),
              onPressed: () => fs.rearmPriceAlert(alert.id),
              tooltip: '다시 켜기',
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: cs.onSurface.withValues(alpha: 0.4),
            onPressed: () => fs.deletePriceAlert(alert.id),
            tooltip: '삭제',
          ),
        ],
      ),
    );
  }
}

/// 한 종목의 조건 알림 목록 바텀시트 (관심종목 벨 버튼).
/// '추가'를 누르면 true 로 pop 하고, 바깥에서 에디터 시트를 연다.
class _StockAlertsSheet extends StatelessWidget {
  const _StockAlertsSheet({required this.pick});

  final StockPick pick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = FirestoreService();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: _alertAccent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${pick.name} 조건 알림',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (uid.isEmpty)
              Text(
                '로그인하면 조건 알림을 설정할 수 있어요',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              )
            else
              StreamBuilder<List<PriceAlert>>(
                stream: fs.watchPriceAlertsForStock(
                  uid,
                  pick.ticker,
                  pick.market,
                ),
                builder: (context, snapshot) {
                  final alerts = snapshot.data ?? const <PriceAlert>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (alerts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '아직 걸어둔 알림이 없어요. 목표가나 등락률을 설정해보세요.',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.45),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      for (final a in alerts) ...[
                        _AlertRow(alert: a, fs: fs),
                        const SizedBox(height: 8),
                      ],
                      _AddButton(onTap: () => Navigator.pop(context, true)),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 조건 알림 설정 바텀시트.
class _AlertEditorSheet extends StatefulWidget {
  const _AlertEditorSheet({required this.pick, required this.currentPrice});
  final StockPick pick;
  final double? currentPrice;

  @override
  State<_AlertEditorSheet> createState() => _AlertEditorSheetState();
}

class _AlertEditorSheetState extends State<_AlertEditorSheet> {
  // 0 = 목표가, 1 = 등락률
  int _mode = 0;
  // 목표가: above/below, 등락률: up/down
  bool _isUp = true;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 목표가 기본값: 현재가 근처
    final p = widget.currentPrice;
    if (p != null && p > 0) {
      _controller.text = widget.pick.market == 'US'
          ? p.toStringAsFixed(2)
          : p.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onModeChange(int m) {
    setState(() {
      _mode = m;
      if (m == 1) {
        _controller.text = '5';
      } else {
        final p = widget.currentPrice;
        _controller.text = p == null || p <= 0
            ? ''
            : widget.pick.market == 'US'
            ? p.toStringAsFixed(2)
            : p.toStringAsFixed(0);
      }
      _isUp = true;
    });
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('올바른 값을 입력해주세요')));
      return;
    }
    final AlertType type;
    if (_mode == 0) {
      type = _isUp ? AlertType.priceAbove : AlertType.priceBelow;
    } else {
      type = _isUp ? AlertType.changeUp : AlertType.changeDown;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    Navigator.pop(
      context,
      PriceAlert(
        id: '',
        uid: uid,
        ticker: widget.pick.ticker.trim().toUpperCase(),
        name: widget.pick.name,
        market: widget.pick.market.trim().toUpperCase(),
        type: type,
        value: value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUS = widget.pick.market == 'US';
    final unit = _mode == 1 ? '%' : (isUS ? '\$' : '₩');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${widget.pick.name} 알림 설정',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            // 모드 세그먼트
            _Segment(
              options: const ['목표가 도달', '등락률'],
              selected: _mode,
              onChanged: _onModeChange,
            ),
            const SizedBox(height: 14),
            // 방향 세그먼트
            _Segment(
              options: _mode == 0
                  ? const ['이상 ↑', '이하 ↓']
                  : const ['상승 ↑', '하락 ↓'],
              selected: _isUp ? 0 : 1,
              onChanged: (i) => setState(() => _isUp = i == 0),
              upDownColors: true,
            ),
            const SizedBox(height: 16),
            // 값 입력
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                prefixText: _mode == 1 ? null : '$unit ',
                suffixText: _mode == 1 ? ' %' : null,
                prefixStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                suffixStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_mode == 0 && widget.currentPrice != null) ...[
              const SizedBox(height: 8),
              Text(
                '현재가 ${isUS ? '\$${widget.currentPrice!.toStringAsFixed(2)}' : '₩${widget.currentPrice!.toStringAsFixed(0)}'}',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isUS
                        ? '미국 정규장(한국시간 밤 11시 30분~새벽 6시)에만 확인해요'
                        : '국내 정규장(09:00~15:30)에만 확인해요',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _submit,
                child: const Text(
                  '알림 설정',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.upDownColors = false,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool upDownColors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? (upDownColors
                              ? (i == 0
                                    ? const Color(0xFFF04452)
                                    : const Color(0xFF1677FF))
                              : const Color(0xFF10B981))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      options[i],
                      style: TextStyle(
                        color: selected == i
                            ? Colors.white
                            : cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
