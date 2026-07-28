import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/admin_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/community_screen.dart';
import '../screens/home_screen.dart' show StockPicksListScreen;
import '../screens/index_detail_screen.dart';
import '../screens/market_analysis_screen.dart';
import '../screens/market_sentiment_screen.dart';
import '../screens/night_futures_chart_screen.dart';
import '../screens/stock_ai_analysis_list_screen.dart';
import '../services/auth_service.dart';
import 'web_login_sheet.dart';

/// 웹 전용 셸 — 8개 핵심 기능만 노출한다.
/// 넓은 화면: 좌측 NavigationRail / 좁은 화면: Drawer.
class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  int _index = 0;
  bool _isAdmin = false;
  // 관리자 패널은 처음 열 때까지 만들지 않는다(탭마다 Firestore 조회가 있다).
  bool _adminOpened = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _isAdmin = _adminUid(FirebaseAuth.instance.currentUser);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final isAdmin = _adminUid(user);
      if (isAdmin == _isAdmin || !mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        if (!isAdmin) {
          _adminOpened = false;
          if (_index >= _dests.length) _index = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  static bool _adminUid(User? user) =>
      user != null && AuthService.adminUids.contains(user.uid);

  static const _adminDest =
      (_IconPair(Icons.shield_outlined, Icons.shield), '관리자');

  List<(_IconPair, String)> get _visibleDests => [
        ..._dests,
        if (_isAdmin) _adminDest,
      ];

  List<Widget> get _visiblePages => [
        ..._pages,
        if (_isAdmin)
          _adminOpened
              ? const AdminScreen(embedded: true)
              : const SizedBox.shrink(),
      ];

  bool get _onAdminPage => _isAdmin && _index == _dests.length;

  static const _dests = <(_IconPair, String)>[
    (_IconPair(Icons.auto_awesome_outlined, Icons.auto_awesome), 'AI 종목분석'),
    (_IconPair(Icons.star_outline, Icons.star), '추천주'),
    (_IconPair(Icons.forum_outlined, Icons.forum), '자유게시판'),
    (_IconPair(Icons.article_outlined, Icons.article), '시황분석글'),
    (_IconPair(Icons.nightlight_outlined, Icons.nightlight), '야간선물'),
    (_IconPair(Icons.show_chart_outlined, Icons.show_chart), '실시간 지수'),
    (_IconPair(Icons.event_outlined, Icons.event), '경제 캘린더'),
    (_IconPair(Icons.psychology_outlined, Icons.psychology), '시장심리지표'),
  ];

  // IndexedStack 으로 각 화면 상태를 유지한다.
  static const _pages = <Widget>[
    StockAiAnalysisListScreen(),
    StockPicksListScreen(),
    CommunityScreen(),
    MarketAnalysisScreen(),
    _WebNightFuturesPage(),
    _WebIndicesPage(),
    CalendarScreen(),
    MarketSentimentScreen(),
  ];

  void _select(int i) => setState(() {
        _index = i;
        if (_isAdmin && i == _dests.length) _adminOpened = true;
      });

  @override
  Widget build(BuildContext context) {
    final dests = _visibleDests;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        // 모바일용으로 설계된 화면이라 본문 폭을 제한해 데스크탑에서도 자연스럽게.
        // 관리자 패널은 입력 폼이 많아 조금 더 넓게 쓴다.
        final body = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _onAdminPage ? 1040 : 720),
            child: IndexedStack(index: _index, children: _visiblePages),
          ),
        );

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _WebRail(
                  index: _index,
                  dests: dests,
                  onSelect: _select,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(dests[_index].$2),
            actions: const [_LoginAction()],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const _BrandHeader(),
                  for (var i = 0; i < dests.length; i++)
                    ListTile(
                      leading: Icon(
                        i == _index
                            ? dests[i].$1.active
                            : dests[i].$1.inactive,
                      ),
                      title: Text(dests[i].$2),
                      selected: i == _index,
                      onTap: () {
                        Navigator.pop(context);
                        _select(i);
                      },
                    ),
                ],
              ),
            ),
          ),
          body: body,
        );
      },
    );
  }
}

class _WebRail extends StatelessWidget {
  const _WebRail({
    required this.index,
    required this.dests,
    required this.onSelect,
  });
  final int index;
  final List<(_IconPair, String)> dests;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (var i = 0; i < dests.length; i++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: _RailTile(
                      icon: i == index
                          ? dests[i].$1.active
                          : dests[i].$1.inactive,
                      label: dests[i].$2,
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(12),
            child: _LoginAction(expanded: true),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.candlestick_chart,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            '주식저장소',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// 로그인 상태에 따라 로그인 버튼 / 프로필(로그아웃) 표시.
class _LoginAction extends StatelessWidget {
  const _LoginAction({this.expanded = false});
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          final btn = FilledButton.icon(
            onPressed: () => WebLoginSheet.show(context),
            icon: const Icon(Icons.login, size: 18),
            label: const Text('로그인'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
        }
        return PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'logout') FirebaseAuth.instance.signOut();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'logout', child: Text('로그아웃')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(0xFF10B981),
                  child: Icon(Icons.person, size: 16, color: Colors.white),
                ),
                if (expanded) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      user.email ?? '내 계정',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 실시간 지수 랜딩 — 주요 지수 타일 → 상세로 이동.
class _WebIndicesPage extends StatelessWidget {
  const _WebIndicesPage();

  static const _entries = <(String, String)>[
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('나스닥100 선물', 'NQ=F'),
    ('S&P500', '^GSPC'),
    ('나스닥 종합', '^IXIC'),
    ('달러/원', 'KRW=X'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 지수')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final (name, symbol) = _entries[i];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.show_chart, color: Color(0xFF10B981)),
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(symbol),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => IndexDetailScreen(name: name, symbol: symbol),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 야간선물 — 코스피 / 코스닥 세그먼트.
class _WebNightFuturesPage extends StatefulWidget {
  const _WebNightFuturesPage();

  @override
  State<_WebNightFuturesPage> createState() => _WebNightFuturesPageState();
}

class _WebNightFuturesPageState extends State<_WebNightFuturesPage> {
  bool _kosdaq = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('코스피 야간선물')),
              ButtonSegment(value: true, label: Text('코스닥 야간선물')),
            ],
            selected: {_kosdaq},
            onSelectionChanged: (s) => setState(() => _kosdaq = s.first),
          ),
        ),
        Expanded(
          child: NightFuturesChartScreen(
            key: ValueKey(_kosdaq),
            collection:
                _kosdaq ? 'night_futures_prices_kosdaq' : 'night_futures_prices',
            title: _kosdaq ? '코스닥 야간선물' : '코스피 야간선물',
          ),
        ),
      ],
    );
  }
}

class _IconPair {
  const _IconPair(this.inactive, this.active);
  final IconData inactive;
  final IconData active;
}
