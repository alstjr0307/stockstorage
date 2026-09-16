/// The server stores dates and slot labels in Korean time.
String aiBriefTimeLabel(Map<String, dynamic>? data, {DateTime? now}) {
  if (data == null) return '';
  final slotLabel = data['slotLabel'] as String?;
  final date = DateTime.tryParse(data['date'] as String? ?? '');
  if (date == null) {
    return slotLabel == null ? '기준일 확인 필요' : '기준일 미상 · $slotLabel';
  }
  final kst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  final today =
      date.year == kst.year && date.month == kst.month && date.day == kst.day;
  final dayLabel = today
      ? '오늘'
      : date.year == kst.year
      ? '${date.month}/${date.day}'
      : '${date.year}/${date.month}/${date.day}';
  return slotLabel == null ? dayLabel : '$dayLabel $slotLabel';
}

bool isMorningAiBrief(Map<String, dynamic>? data) =>
    data?['briefingType'] == 'morning' || data?['slot'] == '08';
