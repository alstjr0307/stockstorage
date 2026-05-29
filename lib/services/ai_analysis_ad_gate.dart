import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'ad_service.dart';
import 'ai_analysis_quota_service.dart';
import 'firestore_service.dart';

/// 새 AI 분석을 실행하기 전 광고 + 쿼터 게이트.
/// 어느 진입점(목록 FAB / 종목 상세 / 재분석 버튼)에서든 동일하게 사용.
class AiAnalysisAdGate {
  AiAnalysisAdGate._();

  /// 임시로 광고/쿼터 제한을 끄려면 true. 운영 복귀 시 false로.
  static const bool _bypassAll = false;

  /// 광고는 유지하되 일일 한도만 임시로 끄려면 true. 운영 복귀 시 false로.
  static const bool _bypassQuota = false;

  /// 일일 쿼터 시스템이 활성화되어 있는지 여부. UI(쿼터 배너 등)는 이 값으로 분기.
  static bool get isQuotaActive => !_bypassQuota && !_bypassAll;

  /// 진행 가능하면 true. 릴리즈 빌드에서 관리자는 우회(디버그에서는 테스트 광고 확인을 위해 정상 진행).
  static Future<bool> run(BuildContext context, String uid) async {
    if (_bypassAll) return true;
    if (AdService.isAdmin && !kDebugMode) return true;

    final firestore = FirestoreService();
    final quota = AiAnalysisQuotaService.instance;

    final level = await firestore.watchPublicUserLevel(uid).first;

    int used = 0;
    int limit = 0;
    if (!_bypassQuota) {
      used = await quota.getUsedToday(uid);
      limit = AiAnalysisQuotaService.dailyLimitForLevel(level);
      if (!context.mounted) return false;
      if (used >= limit) {
        await _showQuotaExhausted(context, level: level, limit: limit);
        return false;
      }
    }

    if (!context.mounted) return false;

    final confirmed = await _showConfirm(
      context,
      used: used,
      limit: limit,
      level: level,
      showQuota: !_bypassQuota,
    );
    if (confirmed != true || !context.mounted) return false;

    final rewarded = await AdService.instance.showAiAnalysisRewardedAd();
    if (!rewarded) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고를 끝까지 시청해야 분석을 시작할 수 있어요.')),
        );
      }
      return false;
    }

    if (!_bypassQuota) {
      await quota.consumeOne(uid);
    }
    return true;
  }

  static Future<bool?> _showConfirm(
    BuildContext context, {
    required int used,
    required int limit,
    required int level,
    bool showQuota = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final remaining = limit - used;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF10B981), size: 22),
            const SizedBox(width: 8),
            Text(
              '광고 시청 후 AI 분석',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '짧은 보상형 광고를 시청한 뒤 새 AI 분석을 시작합니다.',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (showQuota) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오늘 남은 횟수 $remaining / $limit회 (Lv.$level)',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '레벨이 오를수록 하루에 분석할 수 있는 횟수가 늘어납니다.',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text(
              '광고 보기',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showQuotaExhausted(
    BuildContext context, {
    required int level,
    required int limit,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          '오늘 분석 한도를 모두 사용했어요',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Text(
          '현재 Lv.$level 기준 하루 $limit회까지 분석할 수 있어요.\n'
          '레벨을 올리면 더 많이 분석할 수 있어요.\n'
          '내일 다시 시도해주세요.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '확인',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
