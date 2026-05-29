import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';

const _onboardingPrefsKey = 'onboarding_completed_v1';

Future<bool> shouldShowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingPrefsKey) != true;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingPrefsKey, true);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _accent = Color(0xFF10B981);

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.savings_rounded,
      title: '주식 정보를 한 곳에 모아두는 저장소',
      body: '추천주, AI 종합 분석, 시황분석,\n그리고 투자자 커뮤니티까지 — 흩어져 있던 정보를\n주식저장소 하나로 정리하세요.',
    ),
    _OnboardingPage(
      icon: Icons.star_rounded,
      title: '마음에 드는 종목을 저장해보세요',
      body: '홈에서 추천 종목과 시황분석글을 받아보고\n눈에 들어오는 종목은 관심종목에 저장해\n실시간 시세, 목표가 대비 수익률,\n나만의 매매 메모를 관리할 수 있어요.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'AI가 종목과 시장을 한눈에 풀어줘요',
      body: '한국·미국 어떤 종목이든 뉴스·차트·재무·모멘텀을\n종합한 점수와 리포트를 받아볼 수 있어요.\n주요 지수·시장 심리·수급·커뮤니티 HOT 종목까지\n한 번에 확인하세요.',
    ),
    _OnboardingPage(
      icon: Icons.forum_rounded,
      title: '매매일지를 작성하고 커뮤니티에서 공유하세요',
      body: '매수·매도 기록을 매매일지에 남기고,\n커뮤니티에서 주식 관련 얘기를 나눌 수 있어요.\n출석 체크와 데일리 미션으로 레벨을 올리면\nAI 분석 하루 한도와 혜택이 함께 커집니다.',
    ),
  ];

  Future<void> _goLogin() async {
    await markOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(fromOnboarding: true),
      ),
    );
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _goLogin();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _OnboardingPageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final selected = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: selected ? 22 : 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? _accent
                        : cs.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _next,
                  child: Text(
                    isLast ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Icon(
                    page.icon,
                    size: 52,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
