import 'package:flutter/material.dart';

// 파일명: check_medication_detail_ui_boundary.dart
// 역할: 약 상세 정보와 음성 안내 화면의 placeholder UI를 정의한다.

// 클래스명: CheckMedicationDetailUI
// 역할: 후속 상세 정보/음성 안내 기능에서 사용할 UI boundary 계약을 보존한다.
// 주요 책임:
// - 약 상세 정보 문자열을 반환하는 임시 메서드를 제공한다.
// - 음성 안내 기능 연결 지점을 유지한다.
// - 현재는 실제 화면 대신 빈 화면을 렌더링한다.
class CheckMedicationDetailUI extends StatelessWidget {
  final String resultvoiceGuide;
  final String resultmedicationDetail;

  const CheckMedicationDetailUI({
    super.key,
    this.resultvoiceGuide = '',
    this.resultmedicationDetail = '',
  });

  String showMedicationDetail() {
    return resultmedicationDetail;
  }

  void clickVoiceGuide() {}

  String playVoiceGuide() {
    return resultvoiceGuide;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
