import 'package:flutter/material.dart';

// 파일명: check_today_medication_info_ui_boundary.dart
// 역할: 오늘의 복약 정보 요약 화면의 placeholder UI를 정의한다.

// 클래스명: CheckTodayMedicationInfoUI
// 역할: 후속 오늘의 복약 정보 기능에서 사용할 UI boundary 계약을 보존한다.
// 주요 책임:
// - 현재는 미구현 상태를 빈 화면으로 유지한다.
// - 오늘의 복약 정보 화면 진입점을 명시적으로 남긴다.
class CheckTodayMedicationInfoUI extends StatelessWidget {
  const CheckTodayMedicationInfoUI({super.key});

  void clickTodayMedicationInfo() {}

  Widget showTodayMedicationInfo() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
