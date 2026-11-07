// 파일명: medbuddy_confirm_dialog.dart
// 역할: 여러 화면이 함께 쓰는 취소·확인 두 버튼 확인 대화상자를 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// Function Name: showMedBuddyConfirmDialog
// Description: Show a standard confirmation dialog; treat cancellation, back navigation and barrier dismissal as false.
// Parameters: context (BuildContext): navigator context; title (String?): heading; message/cancelLabel/confirmLabel (String): content and labels; dialogKey/cancelKey/confirmKey (Key?): widget IDs; destructive (bool): danger confirmation color; cancelForeground (Color?): cancel text color; barrierDismissible (bool): outside-tap dismissal; scrollable (bool): scroll dialog content.
// Returns: Future<bool>: true only when confirmed.
Future<bool> showMedBuddyConfirmDialog(
  BuildContext context, {
  String? title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  Key? dialogKey,
  Key? cancelKey,
  Key? confirmKey,
  bool destructive = false,
  Color? cancelForeground,
  bool barrierDismissible = true,
  bool scrollable = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    // 함수이름: showMedBuddyConfirmDialog.builder 콜백
    // 함수역할: 전달받은 문구·키·색으로 두 버튼 확인 대화상자를 구성한다.
    // 매개변수:
    // - dialogContext (BuildContext): 대화상자를 닫을 때 쓰는 대화상자 위젯 트리 위치.
    // 반환값: 확인 대화상자 위젯.
    builder: (dialogContext) => AlertDialog(
      key: dialogKey,
      scrollable: scrollable,
      title: title == null ? null : Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: cancelKey,
          style: cancelForeground == null
              ? null
              : TextButton.styleFrom(foregroundColor: cancelForeground),
          // 함수이름: showMedBuddyConfirmDialog.onPressed 콜백
          // 함수역할: 취소 결과 false로 대화상자를 닫는다.
          // 매개변수:
          // - 없음.
          // 반환값: 콜백 결과는 없으며 선택값은 대화상자 종료 결과로 전달한다.
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: MedBuddyColors.danger)
              : null,
          // 함수이름: showMedBuddyConfirmDialog.onPressed 콜백
          // 함수역할: 확인 결과 true로 대화상자를 닫는다.
          // 매개변수:
          // - 없음.
          // 반환값: 콜백 결과는 없으며 선택값은 대화상자 종료 결과로 전달한다.
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
