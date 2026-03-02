import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/stock_card.dart';
import 'stock_detail_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  String _selectedCategory = '전체';
  final List<String> _categories = ['전체', '단기', '중기', '장기'];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        title: Text(
          'StockStorage',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF4ADE80)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            icon: Icon(
              auth.isLoggedIn ? Icons.person : Icons.person_outline,
              color: Colors.white70,
            ),
            onPressed: () {
              if (auth.isLoggedIn) {
                _showProfileMenu(context, auth);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildCategoryFilter(),
          Expanded(child: _buildStockList(auth)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF4ADE80),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '추천주 피드',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4ADE80) : const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFF4ADE80) : Colors.white12,
                ),
              ),
              child: Center(
                child: Text(
                  cat,
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.black : Colors.white60,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStockList(AuthProvider auth) {
    return StreamBuilder<List<StockPick>>(
      stream: _firestoreService.getStockPicks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF4ADE80)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '오류: ${snapshot.error}',
              style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              '아직 추천주가 없습니다',
              style: GoogleFonts.inter(color: Colors.white38),
            ),
          );
        }

        final picks = _selectedCategory == '전체'
            ? snapshot.data!
            : snapshot.data!
                .where((p) => p.category == _selectedCategory)
                .toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          itemCount: picks.length,
          itemBuilder: (context, index) {
            return StockCard(
              pick: picks[index],
              isLoggedIn: auth.isLoggedIn,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StockDetailScreen(pick: picks[index]),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileMenu(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              auth.user?.email ?? '',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  foregroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  auth.signOut();
                },
                child: const Text('로그아웃'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
