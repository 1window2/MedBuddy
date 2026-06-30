import 'package:flutter/material.dart';

// 파일명: check_guardian_medication_ui_boundary.dart
// 역할: 보호자 복약 정보 확인 화면의 placeholder UI를 정의한다.

// 클래스명: CheckGuardianMedicationUI
// 역할: 후속 보호자 기능에서 환자의 복약 정보를 확인하는 화면으로 확장될 진입점이다.
// 주요 책임:
// - 현재는 미구현 상태를 빈 화면으로 유지한다.
// - 클래스 다이어그램의 UI boundary 계약을 보존한다.
class CheckGuardianMedicationUI extends StatelessWidget {
  const CheckGuardianMedicationUI({super.key});

  void clickGuardianMedication() {}

  Widget showGuardianMedication() {
    return this;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
