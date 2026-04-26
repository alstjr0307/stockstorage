import 'package:flutter/material.dart';

Future<String?> showReportReasonDialog(BuildContext context) {
  final reasons = ['스팸', '허위 정보', '불쾌한 내용', '투자 사기 의심', '기타'];
  return showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: const Text('신고 사유를 선택해주세요'),
      children: reasons
          .map(
            (r) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r),
              child: Text(r),
            ),
          )
          .toList(),
    ),
  );
}

Future<bool?> showBlockConfirmDialog(BuildContext context, String nickname) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('차단'),
      content: Text('$nickname 님을 차단하시겠습니까?\n차단된 유저의 댓글은 보이지 않습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('차단', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
}
