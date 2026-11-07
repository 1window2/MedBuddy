// 파일명: medication_candidate_dialog.dart
// 역할: 검색 후보의 이름·함량·제형을 확인한 뒤 선택한 약품 또는 취소 결과를 돌려준다.

import 'package:flutter/material.dart';

import '../entities/medication_detail_entity.dart';

// 클래스명: MedicationCandidateDialog
// 역할: 약품 후보를 명시적으로 확인하는 선택 대화상자.
// 주요 책임: 선택 전 확인 버튼을 비활성화하고 취소와 확정을 구분한다.
// 속성: originalName (String): 입력 약명; candidates (List<MedicationDetail>): 비교 후보; isEnglish (bool): 표시 언어.
class MedicationCandidateDialog extends StatefulWidget {
  final String originalName;
  final List<MedicationDetail> candidates;
  final bool isEnglish;

  // 함수이름: MedicationCandidateDialog
  // 함수역할: 초기 선택 없이 비교할 약명과 후보 목록을 받는다.
  // 매개변수: key (Key?): 위젯 키; originalName (String): 입력 약명; candidates (List<MedicationDetail>): 후보; isEnglish (bool): 영어 여부.
  // 반환값: 새 MedicationCandidateDialog.
  const MedicationCandidateDialog({
    super.key,
    required this.originalName,
    required this.candidates,
    this.isEnglish = false,
  });

  // 함수이름: createState
  // 함수역할: 후보 선택과 한 번만 닫기 위한 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _MedicationCandidateDialogState.
  @override
  State<MedicationCandidateDialog> createState() =>
      _MedicationCandidateDialogState();
}

// 클래스명: _MedicationCandidateDialogState
// 역할: 후보 선택과 화면 종료 중복을 관리한다.
// 주요 책임: 현재 대화상자만 한 번 닫아 아래 화면이 함께 닫히지 않게 한다.
// 속성: _selected (MedicationDetail?): 선택 후보; _isClosing (bool): 종료 시작 여부.
class _MedicationCandidateDialogState extends State<MedicationCandidateDialog> {
  MedicationDetail? _selected;
  bool _isClosing = false;

  // 함수이름: _close
  // 함수역할: 종료 중이거나 현재 경로가 아니면 무시하고, 그 외에는 한 번만 결과를 반환하며 닫는다.
  // 매개변수: selected (MedicationDetail?): 확정 후보; 생략하면 취소.
  // 반환값: 없음. 경로 결과로 후보 또는 null을 전달한다.
  void _close([MedicationDetail? selected]) {
    if (_isClosing || ModalRoute.of(context)?.isCurrent != true) return;
    _isClosing = true;
    Navigator.pop(context, selected);
  }

  // 함수이름: build
  // 함수역할: 전체 약명·제조사와 확인 안내를 표시하고 선택한 후보에만 확정을 허용한다.
  // 매개변수: context (BuildContext): 대화상자 표시 위치.
  // 반환값: 스크롤 가능한 AlertDialog.
  @override
  Widget build(BuildContext context) {
    final english = widget.isEnglish;
    return AlertDialog(
      title: Text(english ? 'Confirm the medication' : '약품 후보 확인'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              english
                  ? 'Medication name: ${widget.originalName}'
                  : '약 이름: ${widget.originalName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              english
                  ? 'Compare the full name, strength and dosage form with your prescription. Cancel if unsure.'
                  : '처방전의 전체 약 이름·함량·제형이 같은지 확인해주세요. 확실하지 않으면 취소해주세요.',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.candidates.length; i++)
              ListTile(
                key: Key('medication-candidate-$i'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  identical(_selected, widget.candidates[i])
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                selected: identical(_selected, widget.candidates[i]),
                title: Text(widget.candidates[i].itemName),
                subtitle: Text(
                  widget.candidates[i].manufacturer.isEmpty
                      ? (english ? 'Manufacturer unavailable' : '제조사 정보 없음')
                      : widget.candidates[i].manufacturer,
                ),
                onTap: () => setState(() => _selected = widget.candidates[i]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _close(),
          child: Text(english ? 'Cancel' : '취소'),
        ),
        FilledButton(
          key: const Key('confirm-medication-candidate'),
          onPressed: _selected == null ? null : () => _close(_selected),
          child: Text(english ? 'Confirm this medication' : '이 약으로 확인'),
        ),
      ],
    );
  }
}
