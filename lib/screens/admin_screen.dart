import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  final _tickerController = TextEditingController();
  final _nameController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _targetPriceController = TextEditingController();
  final _reasonController = TextEditingController();

  String _category = '단기';
  bool _isPremium = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _tickerController.dispose();
    _nameController.dispose();
    _buyPriceController.dispose();
    _targetPriceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '추천주 등록',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildField('티커 (예: 005930)', _tickerController, hint: 'TICKER'),
            const SizedBox(height: 14),
            _buildField('종목명', _nameController, hint: '삼성전자'),
            const SizedBox(height: 14),
            _buildField('매수가', _buyPriceController, hint: '70000', isNumber: true),
            const SizedBox(height: 14),
            _buildField('목표가', _targetPriceController, hint: '85000', isNumber: true),
            const SizedBox(height: 14),
            _buildField('매수 근거', _reasonController, hint: '매수 근거를 입력하세요...', maxLines: 5),
            const SizedBox(height: 20),
            // 카테고리
            Text('투자 기간', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: ['단기', '중기', '장기'].map((cat) {
                final isSelected = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF4ADE80) : const Color(0xFF1A2035),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF4ADE80) : Colors.white12,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.black : Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 프리미엄 토글
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '프리미엄 콘텐츠',
                  style: GoogleFonts.inter(color: Colors.white70),
                ),
                subtitle: Text(
                  '로그인 사용자만 상세 열람 가능',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                ),
                value: _isPremium,
                activeColor: const Color(0xFFFFD700),
                onChanged: (val) => setState(() => _isPremium = val),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        '등록하기',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF1A2035),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4ADE80), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (val) => val == null || val.isEmpty ? '$label을 입력하세요' : null,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final pick = StockPick(
        id: '',
        ticker: _tickerController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        buyPrice: double.parse(_buyPriceController.text.replaceAll(',', '')),
        targetPrice: double.parse(_targetPriceController.text.replaceAll(',', '')),
        reason: _reasonController.text.trim(),
        category: _category,
        isPremium: _isPremium,
        createdAt: DateTime.now(),
      );

      await _firestoreService.addStockPick(pick);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pick.name} 등록 완료!',
                style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF4ADE80),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
