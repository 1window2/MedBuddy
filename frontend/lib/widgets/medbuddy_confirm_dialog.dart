// 파일명: medbuddy_confirm_dialog.dart
// 역할: 여러 화면이 함께 쓰는 취소·확인 두 버튼 확인 대화상자를 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 함수이름: showMedBuddyConfirmDialog
// 함수역할:
// - 제목(선택)과 안내 문구, 취소 TextButton과 확인 FilledButton으로 이루어진 확인 대화상자를 연다.
// - 취소를 누르면 false, 확인을 누르면 true로 대화상자를 닫는다.
// 매개변수:
// - context (BuildContext): 대화상자를 띄울 위젯 트리 위치.
// - title (String?): 대화상자 제목; null이면 제목 없이 안내 문구만 표시한다.
// - message (String): 대화상자 본문 안내 문구.
// - cancelLabel (String): 취소 버튼 문구.
// - confirmLabel (String): 확인 버튼 문구.
// - dialogKey (Key?): AlertDialog에 붙일 위젯 키.
// - cancelKey (Key?): 취소 버튼에 붙일 위젯 키.
// - confirmKey (Key?): 확인 버튼에 붙일 위젯 키.
// - destructive (bool): true이면 확인 버튼을 위험 색(MedBuddyColors.danger)으로 채운다.
// - cancelForeground (Color?): 취소 버튼 글자색; null이면 테마 기본값을 쓴다.
// - barrierDismissible (bool): 바깥을 눌러 대화상자를 닫을 수 있는지 여부.
// - scrollable (bool): 긴 안내 문구를 대화상자 안에서 스크롤할지 여부.
// 반환값:
// - Future<bool>: 확인을 누르면 true, 취소하거나 바깥을 눌러 닫으면 false.
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
