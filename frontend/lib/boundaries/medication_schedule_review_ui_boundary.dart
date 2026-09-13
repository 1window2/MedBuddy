import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_schedule_review_ui_boundary.dart
// 역할: 저장 전 여러 약의 복약 일정 비교·수정·검증을 제공한다.

// 클래스명: MedicationScheduleReviewPurpose
// 역할: 처방전·알약·직접 입력별 검토 목적을 담당한다.
// 주요 책임:
// - 처방전·알약·직접 입력별 검토 목적에서 지원하는 선택지를 열거하고 구분한다: prescriptionAnalysis, pillSave.
enum MedicationScheduleReviewPurpose { prescriptionAnalysis, pillSave }

// 함수이름: showMedicationScheduleReview
// 함수역할: 인식된 하나 이상의 복약 일정을 한 화면에서 검토하게 한다. 사용자가 취소하면 null, 확인하면 정규화된 일정 목록을 반환한다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - initialSchedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - purpose (MedicationScheduleReviewPurpose): 처방전·알약·직접 입력별 일정 검토 목적.
// 반환값: Future<List<MedicationSchedule>?>: 확정한 복약 일정 목록; 입력이 없거나 취소하면 null.
Future<List<MedicationSchedule>?> showMedicationScheduleReview({
  required BuildContext context,
  required List<MedicationSchedule> initialSchedules,
  required UserSetting userSetting,
  required MedicationScheduleReviewPurpose purpose,
}) {
  if (initialSchedules.isEmpty) {
    return Future.value(null);
  }

  final normalizedSchedules = initialSchedules
      .map(
        // 함수이름: showMedicationScheduleReview.map callback
        // 함수역할: 저장 전 여러 약의 복약 일정 비교·수정·검증의 변환값을 `_normalizeSchedule(schedule, usePillDefaults: purpose == MedicationScheduleReviewPurpose.pillSave)` 규칙으로 계산한다.
        // 매개변수:
        // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        (schedule) => _normalizeSchedule(
          schedule,
          usePillDefaults: purpose == MedicationScheduleReviewPurpose.pillSave,
        ),
      )
      .toList(growable: false);

  return showModalBottomSheet<List<MedicationSchedule>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // 함수이름: showMedicationScheduleReview.builder callback
    // 함수역할: 저장 전 여러 약의 복약 일정 비교·수정·검증에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
    // 매개변수:
    // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
    // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _MedicationScheduleReviewSheet(
        initialSchedules: normalizedSchedules,
        userSetting: userSetting,
        purpose: purpose,
      ),
    ),
  );
}

// 함수이름: showMedicationScheduleEditor
// 함수역할: 복약 일정 한 건의 시작일, 복용량, 횟수, 기간과 시간대를 수정하게 한다.
// 매개변수:
// - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// 반환값: Future<MedicationSchedule?>: 확정한 복약 일정; 취소 시 null.
Future<MedicationSchedule?> showMedicationScheduleEditor({
  required BuildContext context,
  required MedicationSchedule medicationSchedule,
  required UserSetting userSetting,
}) {
  return showDialog<MedicationSchedule>(
    context: context,
    // 함수이름: showMedicationScheduleEditor.builder callback
    // 함수역할: 저장 전 여러 약의 복약 일정 비교·수정·검증에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
    // 매개변수:
    // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
    // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
    builder: (dialogContext) => _MedicationScheduleEditorDialog(
      medicationSchedule: medicationSchedule,
      userSetting: userSetting,
    ),
  );
}

// 클래스명: _MedicationScheduleReviewSheet
// 역할: 여러 약의 복용 일정 비교와 저장 전 확인을 담당한다.
// 주요 책임:
// - 여러 약의 복용 일정 비교와 저장 전 확인의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - initialSchedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - purpose (MedicationScheduleReviewPurpose): 처방전·알약·직접 입력별 일정 검토 목적.
class _MedicationScheduleReviewSheet extends StatefulWidget {
  final List<MedicationSchedule> initialSchedules;
  final UserSetting userSetting;
  final MedicationScheduleReviewPurpose purpose;

  // 함수이름: _MedicationScheduleReviewSheet
  // 함수역할: 여러 약의 복용 일정 비교와 저장 전 확인에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - initialSchedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - purpose (MedicationScheduleReviewPurpose): 처방전·알약·직접 입력별 일정 검토 목적.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleReviewSheet 인스턴스.
  const _MedicationScheduleReviewSheet({
    required this.initialSchedules,
    required this.userSetting,
    required this.purpose,
  });

  // 함수이름: createState
  // 함수역할: 여러 약의 복용 일정 비교와 저장 전 확인의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _MedicationScheduleReviewSheetState 인스턴스.
  @override
  State<_MedicationScheduleReviewSheet> createState() =>
      _MedicationScheduleReviewSheetState();
}

// 클래스명: _MedicationScheduleReviewSheetState
// 역할: 여러 약의 복용 일정 비교와 저장 전 확인의 화면 상태를 관리한다.
// 주요 책임:
// - 선택한 약의 편집 창 결과를 같은 위치에 반영하고 이전 검증 안내를 지운다.
// 속성:
// - _schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
class _MedicationScheduleReviewSheetState
    extends State<_MedicationScheduleReviewSheet> {
  late List<MedicationSchedule> _schedules;
  String _validationMessage = '';

  // 함수이름: initState
  // 함수역할: 호출자가 전달한 일정을 별도 수정 가능한 목록으로 복사한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _schedules = List<MedicationSchedule>.of(widget.initialSchedules);
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 여러 약의 복용 일정 비교와 저장 전 확인 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 여러 약의 복용 일정 비교와 저장 전 확인에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _MedicationScheduleReviewText(widget.userSetting.language);
    final scale = widget.userSetting.contentTextScale;
    final isPillSave =
        widget.purpose == MedicationScheduleReviewPurpose.pillSave;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 10),
            child: Row(
              children: [
                IconButton(
                  key: const Key('schedule-review-close'),
                  tooltip: text.cancel,
                  // 함수이름: build.onPressed callback
                  // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    text.reviewTitle,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('schedule-review-list'),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              children: [
                Text(
                  isPillSave
                      ? text.pillReviewDescription
                      : text.prescriptionReviewDescription,
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14 * scale,
                    height: 1.45,
                    letterSpacing: 0,
                  ),
                ),
                if (isPillSave) ...[
                  const SizedBox(height: 14),
                  _PillScheduleSafetyNotice(text: text, scale: scale),
                ],
                if (_validationMessage.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ScheduleValidationNotice(
                    message: _validationMessage,
                    scale: scale,
                  ),
                ],
                const SizedBox(height: 18),
                for (var index = 0; index < _schedules.length; index++) ...[
                  _MedicationScheduleReviewCard(
                    index: index,
                    medicationSchedule: _schedules[index],
                    userSetting: widget.userSetting,
                    // 함수이름: build.onEditRequested callback
                    // 함수역할: 선택한 약의 편집 창 결과를 같은 위치에 반영하고 이전 검증 안내를 지운다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onEditRequested: () => _editSchedule(index),
                  ),
                  if (index < _schedules.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: MedBuddyColors.outline)),
            ),
            child: FilledButton(
              key: const Key('schedule-review-confirm'),
              onPressed: _confirmReview,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: MedBuddyColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isPillSave ? text.confirmAndSave : text.confirmAndAnalyze,
                style: TextStyle(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 함수이름: _editSchedule
  // 함수역할: 선택한 약의 편집 창 결과를 같은 위치에 반영하고 이전 검증 안내를 지운다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _editSchedule(int index) async {
    final updatedSchedule = await showMedicationScheduleEditor(
      context: context,
      medicationSchedule: _schedules[index],
      userSetting: widget.userSetting,
    );
    if (!mounted || updatedSchedule == null) {
      return;
    }
    // 함수이름: _editSchedule.setState callback
    // 함수역할: 여러 약의 복용 일정 비교와 저장 전 확인의 입력·요청 상태를 `_schedules[index] = updatedSchedule; _validationMessage = ''`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _schedules[index] = updatedSchedule;
      _validationMessage = '';
    });
  }

  // 함수이름: _confirmReview
  // 함수역할: 누락되거나 서로 맞지 않는 일정이 있으면 해당 약의 수정 창을 열고 유효한 목록만 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _confirmReview() async {
    final invalidIndex = _schedules.indexWhere(
      // 함수이름: _confirmReview.indexWhere callback
      // 함수역할: 여러 약의 복용 일정 비교와 저장 전 확인에 대해 `!_isScheduleComplete(schedule)` 조건으로 컬렉션 항목을 판별한다.
      // 매개변수:
      // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
      // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
      (schedule) => !_isScheduleComplete(schedule),
    );
    if (invalidIndex >= 0) {
      final text = _MedicationScheduleReviewText(widget.userSetting.language);
      // 함수이름: _confirmReview.setState callback
      // 함수역할: 여러 약의 복용 일정 비교와 저장 전 확인의 입력·요청 상태를 `_validationMessage = text.incompleteSchedule(_schedules[invalidIndex].displayNameForLanguage(widg...`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _validationMessage = text.incompleteSchedule(
          _schedules[invalidIndex].displayNameForLanguage(
            widget.userSetting.language,
          ),
        );
      });
      await _editSchedule(invalidIndex);
      return;
    }

    Navigator.pop(context, List<MedicationSchedule>.unmodifiable(_schedules));
  }
}

// 클래스명: _MedicationScheduleReviewCard
// 역할: 약 한 건의 복용 기간·용량·시간대와 수정 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약 한 건의 복용 기간·용량·시간대와 수정 명령 위젯을 구성한다.
// 속성:
// - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onEditRequested (VoidCallback): 선택한 약품 일정·입력란의 편집을 여는 콜백.
class _MedicationScheduleReviewCard extends StatelessWidget {
  final int index;
  final MedicationSchedule medicationSchedule;
  final UserSetting userSetting;
  final VoidCallback onEditRequested;

  // 함수이름: _MedicationScheduleReviewCard
  // 함수역할: 약 한 건의 복용 기간·용량·시간대와 수정 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onEditRequested (VoidCallback): 선택한 약품 일정·입력란의 편집을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleReviewCard 인스턴스.
  const _MedicationScheduleReviewCard({
    required this.index,
    required this.medicationSchedule,
    required this.userSetting,
    required this.onEditRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약 한 건의 복용 기간·용량·시간대와 수정 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약 한 건의 복용 기간·용량·시간대와 수정 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _MedicationScheduleReviewText(userSetting.language);
    final scale = userSetting.contentTextScale;
    final frequency = medicationSchedule.dailyFrequencyCount;
    final slotLabels = medicationSchedule.slotKeys
        .map(text.slotLabel)
        .join(', ');

    return Container(
      key: Key('schedule-review-card-$index'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: MedBuddyColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  medicationSchedule.displayNameForLanguage(
                    userSetting.language,
                  ),
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    letterSpacing: 0,
                  ),
                ),
              ),
              IconButton(
                key: Key('schedule-review-edit-$index'),
                tooltip: text.edit,
                onPressed: onEditRequested,
                icon: const Icon(Icons.edit_outlined),
                color: MedBuddyColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ScheduleSummaryRow(
            label: text.startDate,
            value: _formatDate(medicationSchedule.prescriptionDate),
            emptyValue: text.reviewNeeded,
            scale: scale,
          ),
          _ScheduleSummaryRow(
            label: text.dosage,
            value: medicationSchedule.dosage.trim().isEmpty
                ? ''
                : medicationSchedule.dosageLabelForLanguage(
                    userSetting.language,
                  ),
            emptyValue: text.reviewNeeded,
            scale: scale,
          ),
          _ScheduleSummaryRow(
            label: text.dailyFrequency,
            value: frequency <= 0 ? '' : text.frequencyValue(frequency),
            emptyValue: text.reviewNeeded,
            scale: scale,
          ),
          _ScheduleSummaryRow(
            label: text.duration,
            value: medicationSchedule.medicationTime <= 0
                ? ''
                : text.durationValue(medicationSchedule.medicationTime),
            emptyValue: text.reviewNeeded,
            scale: scale,
          ),
          _ScheduleSummaryRow(
            label: text.scheduleSlots,
            value: slotLabels,
            emptyValue: text.reviewNeeded,
            scale: scale,
          ),
        ],
      ),
    );
  }
}

// 클래스명: _ScheduleSummaryRow
// 역할: 검토용 복약 항목의 라벨과 요약 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 검토용 복약 항목의 라벨과 요약 값 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - emptyValue (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _ScheduleSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String emptyValue;
  final double scale;

  // 함수이름: _ScheduleSummaryRow
  // 함수역할: 검토용 복약 항목의 라벨과 요약 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - emptyValue (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _ScheduleSummaryRow 인스턴스.
  const _ScheduleSummaryRow({
    required this.label,
    required this.value,
    required this.emptyValue,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 검토용 복약 항목의 라벨과 요약 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 검토용 복약 항목의 라벨과 요약 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? emptyValue : value.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 13 * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                color: value.trim().isEmpty
                    ? const Color(0xFF9A6700)
                    : MedBuddyColors.textStrong,
                fontSize: 13 * scale,
                fontWeight: FontWeight.w700,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _PillScheduleSafetyNotice
// 역할: 알약 사진만으로 복약 일정을 확정할 수 없다는 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 알약 사진만으로 복약 일정을 확정할 수 없다는 안내 위젯을 구성한다.
// 속성:
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _PillScheduleSafetyNotice extends StatelessWidget {
  final _MedicationScheduleReviewText text;
  final double scale;

  // 함수이름: _PillScheduleSafetyNotice
  // 함수역할: 알약 사진만으로 복약 일정을 확정할 수 없다는 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_MedicationScheduleReviewText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _PillScheduleSafetyNotice 인스턴스.
  const _PillScheduleSafetyNotice({required this.text, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 알약 사진만으로 복약 일정을 확정할 수 없다는 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 알약 사진만으로 복약 일정을 확정할 수 없다는 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        border: Border.all(color: const Color(0xFFF0C36A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.pillSafetyNotice,
              style: TextStyle(
                color: const Color(0xFF6B4B00),
                fontSize: 13 * scale,
                fontWeight: FontWeight.w600,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _ScheduleValidationNotice
// 역할: 저장 전 수정이 필요한 복약 정보 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 전 수정이 필요한 복약 정보 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _ScheduleValidationNotice extends StatelessWidget {
  final String message;
  final double scale;

  // 함수이름: _ScheduleValidationNotice
  // 함수역할: 저장 전 수정이 필요한 복약 정보 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _ScheduleValidationNotice 인스턴스.
  const _ScheduleValidationNotice({required this.message, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 전 수정이 필요한 복약 정보 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 전 수정이 필요한 복약 정보 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: const Color(0xFFB42318),
          fontSize: 13 * scale,
          fontWeight: FontWeight.w700,
          height: 1.4,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _MedicationScheduleEditorDialog
// 역할: 단일 약품의 기간·용량·횟수·시간대 수정을 담당한다.
// 주요 책임:
// - 단일 약품의 기간·용량·횟수·시간대 수정의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class _MedicationScheduleEditorDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final UserSetting userSetting;

  // 함수이름: _MedicationScheduleEditorDialog
  // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleEditorDialog 인스턴스.
  const _MedicationScheduleEditorDialog({
    required this.medicationSchedule,
    required this.userSetting,
  });

  // 함수이름: createState
  // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _MedicationScheduleEditorDialogState 인스턴스.
  @override
  State<_MedicationScheduleEditorDialog> createState() =>
      _MedicationScheduleEditorDialogState();
}

// 클래스명: _MedicationScheduleEditorDialogState
// 역할: 단일 약품의 기간·용량·횟수·시간대 수정의 화면 상태를 관리한다.
// 주요 책임:
// - 복용 횟수에 맞는 기본 시간대 집합으로 교체하고 시간대 검증 오류를 지운다.
// - 시간대 선택을 변경하고 선택 수로 복용 횟수와 빈 선택 오류를 갱신한다.
// - 기존 시작일도 선택 범위에 포함하도록 달력을 열어 확정 날짜를 반영한다.
class _MedicationScheduleEditorDialogState
    extends State<_MedicationScheduleEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _daysController;
  late DateTime _startDate;
  late int _frequencyCount;
  late Set<String> _selectedSlotKeys;
  bool _showSlotValidationError = false;

  // 함수이름: initState
  // 함수역할: 약명·용량·일수를 입력란에 넣고 1~4회 범위의 횟수와 시간대를 일치시킨다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.medicationSchedule.medicationName,
    );
    _dosageController = TextEditingController(
      text: widget.medicationSchedule.dosage,
    );
    _daysController = TextEditingController(
      text: widget.medicationSchedule.medicationTime.toString(),
    );
    _startDate = widget.medicationSchedule.prescriptionDate ?? DateTime.now();
    _frequencyCount = widget.medicationSchedule.dailyFrequencyCount
        .clamp(1, 4)
        .toInt();
    _selectedSlotKeys = widget.medicationSchedule.slotKeys.toSet();
    if (_selectedSlotKeys.isEmpty ||
        _selectedSlotKeys.length != _frequencyCount) {
      _selectedSlotKeys = medicationScheduleSlotKeysForFrequency(
        _frequencyCount,
      ).toSet();
    }
  }

  // 함수이름: dispose
  // 함수역할: _nameController, _dosageController, _daysController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 단일 약품의 기간·용량·횟수·시간대 수정 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 단일 약품의 기간·용량·횟수·시간대 수정에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _MedicationScheduleReviewText(widget.userSetting.language);
    final scale = widget.userSetting.contentTextScale;

    return AlertDialog(
      scrollable: true,
      title: Text(
        text.editTitle,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 21 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const Key('schedule-edit-name'),
              controller: _nameController,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: text.medicationName),
              // 함수이름: build.validator callback
              // 함수역할: 입력값을 `value == null || value.trim().isEmpty ? text.medicationNameRequired : null` 조건으로 검증한다.
              // 매개변수:
              // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
              // 반환값: 유효하지 않으면 검증 문구, 유효하면 null.
              validator: (value) => value == null || value.trim().isEmpty
                  ? text.medicationNameRequired
                  : null,
            ),
            ListTile(
              key: const Key('schedule-edit-start-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(text.startDate),
              subtitle: Text(_formatDate(_startDate)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _selectStartDate,
            ),
            TextFormField(
              key: const Key('schedule-edit-dosage'),
              controller: _dosageController,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: text.dosage,
                hintText: text.dosageHint,
              ),
              // 함수이름: build.validator callback
              // 함수역할: 입력값을 `value == null || value.trim().isEmpty ? text.dosageRequired : null` 조건으로 검증한다.
              // 매개변수:
              // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
              // 반환값: 유효하지 않으면 검증 문구, 유효하면 null.
              validator: (value) => value == null || value.trim().isEmpty
                  ? text.dosageRequired
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              text.dailyFrequency,
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var count = 1; count <= 4; count++)
                  ChoiceChip(
                    key: Key('schedule-edit-frequency-$count'),
                    label: Text(text.frequencyValue(count)),
                    selected: _frequencyCount == count,
                    // 함수이름: build.onSelected callback
                    // 함수역할: 복용 횟수에 맞는 기본 시간대 집합으로 교체하고 시간대 검증 오류를 지운다.
                    // 매개변수:
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onSelected: (_) => _setFrequency(count),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('schedule-edit-days'),
              controller: _daysController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: text.duration),
              validator: _validateDuration,
            ),
            const SizedBox(height: 16),
            Text(
              text.scheduleSlots,
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slotKey in medicationScheduleSlotKeys)
                  FilterChip(
                    key: Key('schedule-edit-slot-$slotKey'),
                    label: Text(text.slotLabel(slotKey)),
                    selected: _selectedSlotKeys.contains(slotKey),
                    // 함수이름: build.onSelected callback
                    // 함수역할: 시간대 선택을 변경하고 선택 수로 복용 횟수와 빈 선택 오류를 갱신한다.
                    // 매개변수:
                    // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onSelected: (selected) => _toggleSlot(slotKey, selected),
                  ),
              ],
            ),
            if (_showSlotValidationError) ...[
              const SizedBox(height: 8),
              Text(
                text.scheduleSlotCountMismatch(_frequencyCount),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12 * scale,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('schedule-edit-cancel'),
          // 함수이름: build.onPressed callback
          // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
          // 매개변수:
          // - 없음.
          // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          key: const Key('schedule-edit-apply'),
          onPressed: _submit,
          child: Text(text.apply),
        ),
      ],
    );
  }

  // 함수이름: _setFrequency
  // 함수역할: 복용 횟수에 맞는 기본 시간대 집합으로 교체하고 시간대 검증 오류를 지운다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _setFrequency(int count) {
    // 함수이름: _setFrequency.setState callback
    // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정의 입력·요청 상태를 `_frequencyCount = count; _selectedSlotKeys = medicationScheduleSlotKeysForFrequency(count).toSet(); _showSlotValidationError = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _frequencyCount = count;
      _selectedSlotKeys = medicationScheduleSlotKeysForFrequency(count).toSet();
      _showSlotValidationError = false;
    });
  }

  // 함수이름: _toggleSlot
  // 함수역할: 시간대 선택을 변경하고 선택 수로 복용 횟수와 빈 선택 오류를 갱신한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // - selected (bool): 현재 선택 집합에 포함되는지 여부.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _toggleSlot(String slotKey, bool selected) {
    // 함수이름: _toggleSlot.setState callback
    // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정의 입력·요청 상태를 `_frequencyCount = _selectedSlotKeys.length.clamp(1, 4).toInt(); _showSlotValidationError = _selectedSlotKeys.isEmpty`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      if (selected) {
        _selectedSlotKeys.add(slotKey);
      } else {
        _selectedSlotKeys.remove(slotKey);
      }
      _frequencyCount = _selectedSlotKeys.length.clamp(1, 4).toInt();
      _showSlotValidationError = _selectedSlotKeys.isEmpty;
    });
  }

  // 함수이름: _selectStartDate
  // 함수역할: 기존 시작일도 선택 범위에 포함하도록 달력을 열어 확정 날짜를 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _selectStartDate() async {
    final standardFirstDate = DateTime(2000);
    final standardLastDate = DateTime.now().add(const Duration(days: 365));
    final firstDate = _startDate.isBefore(standardFirstDate)
        ? _startDate
        : standardFirstDate;
    final lastDate = _startDate.isAfter(standardLastDate)
        ? _startDate
        : standardLastDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!mounted || selectedDate == null) {
      return;
    }
    // 함수이름: _selectStartDate.setState callback
    // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정의 입력·요청 상태를 `_startDate = selectedDate`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _startDate = selectedDate);
  }

  // 함수이름: _validateDuration
  // 함수역할: 복용 기간이 1~3650일의 정수인지 검증한다.
  // 매개변수:
  // - value (String?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? _validateDuration(String? value) {
    final days = int.tryParse(value?.trim() ?? '');
    if (days == null || days <= 0 || days > 3650) {
      return _MedicationScheduleReviewText(
        widget.userSetting.language,
      ).invalidDuration;
    }
    return null;
  }

  // 함수이름: _submit
  // 함수역할: 입력과 시간대 수를 검증하고 확인된 약명·일정 사본을 대화상자 결과로 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _submit() {
    final hasValidSlots =
        _selectedSlotKeys.isNotEmpty &&
        _selectedSlotKeys.length == _frequencyCount;
    if (!hasValidSlots) {
      // 함수이름: _submit.setState callback
      // 함수역할: 단일 약품의 기간·용량·횟수·시간대 수정의 입력·요청 상태를 `_showSlotValidationError = true`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _showSlotValidationError = true);
    }
    if (!(_formKey.currentState?.validate() ?? false) || !hasValidSlots) {
      return;
    }

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: _nameController.text.trim(),
        prescriptionDate: _startDate,
        dosage: _dosageController.text.trim(),
        intakeTime: '$_frequencyCount회',
        medicationTime: int.parse(_daysController.text.trim()),
        scheduleSlotKeys: medicationScheduleSlotKeys
            .where(_selectedSlotKeys.contains)
            .toList(growable: false),
        nameConfidence: 1,
        nameCorrectionSource: 'user_review',
      ),
    );
  }
}

// 함수이름: _normalizeSchedule
// 함수역할: 빈 날짜·비양수 일수·횟수와 시간대 불일치를 보정하고 알약 입력의 빈 용량만 기본값으로 채운다.
// 매개변수:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - usePillDefaults (bool): 알약 식별 결과용 기본 일정 보정 규칙을 적용할지 여부.
// 반환값: MedicationSchedule: 날짜·기간·복용 횟수·시간대를 정규화한 일정 사본.
MedicationSchedule _normalizeSchedule(
  MedicationSchedule schedule, {
  required bool usePillDefaults,
}) {
  final frequency = schedule.dailyFrequencyCount.clamp(1, 4).toInt();
  final slots = schedule.slotKeys.length == frequency
      ? schedule.slotKeys
      : medicationScheduleSlotKeysForFrequency(frequency);
  return schedule.copyWith(
    prescriptionDate: schedule.prescriptionDate ?? DateTime.now(),
    dosage: schedule.dosage.trim().isEmpty && usePillDefaults
        ? '1정'
        : schedule.dosage.trim(),
    intakeTime: '$frequency회',
    medicationTime: schedule.medicationTime <= 0 ? 1 : schedule.medicationTime,
    scheduleSlotKeys: slots,
  );
}

// 함수이름: _isScheduleComplete
// 함수역할: 약명·날짜·용량·1~4회 횟수·1~3650일 기간과 시간대 수의 일치를 확인한다.
// 매개변수:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// 반환값: 설명한 조건을 만족하면 true, 아니면 false.
bool _isScheduleComplete(MedicationSchedule schedule) {
  final frequency = schedule.dailyFrequencyCount;
  return schedule.medicationName.trim().isNotEmpty &&
      schedule.prescriptionDate != null &&
      schedule.dosage.trim().isNotEmpty &&
      frequency >= 1 &&
      frequency <= 4 &&
      schedule.medicationTime >= 1 &&
      schedule.medicationTime <= 3650 &&
      schedule.slotKeys.length == frequency;
}

// 함수이름: _formatDate
// 함수역할: 날짜를 연-월-일로 표시하고 날짜가 없으면 빈 문자열을 사용한다.
// 매개변수:
// - date (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _formatDate(DateTime? date) {
  if (date == null) {
    return '';
  }
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

// 클래스명: _MedicationScheduleReviewText
// 역할: 저장 전 여러 약의 복약 일정 비교·수정·검증에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 저장 전 여러 약의 복약 일정 비교·수정·검증에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _MedicationScheduleReviewText {
  final String language;

  // 함수이름: _MedicationScheduleReviewText
  // 함수역할: 저장 전 여러 약의 복약 일정 비교·수정·검증에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleReviewText 인스턴스.
  const _MedicationScheduleReviewText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';
  // 함수이름: reviewTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get reviewTitle => isEnglish ? 'Review medication plan' : '복약 정보 확인';
  // 함수이름: prescriptionReviewDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "약품 분석 전에 OCR로 인식한 값을 확인해주세요. 잘못된 항목만 수정하면 됩니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionReviewDescription => isEnglish
      ? 'Review the OCR values before medication analysis. Edit only the incorrect entries.'
      : '약품 분석 전에 OCR로 인식한 값을 확인해주세요. 잘못된 항목만 수정하면 됩니다.';
  // 함수이름: pillReviewDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택한 알약 후보의 복용 일정을 설정해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get pillReviewDescription => isEnglish
      ? 'Set a medication plan for the selected pill candidate.'
      : '선택한 알약 후보의 복용 일정을 설정해주세요.';
  // 함수이름: pillSafetyNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 사진만으로 실제 복용량과 기간을 알 수 없습니다. 아래 값은 임시 기본값이므로 처방전이나 약 봉투를 확인한 뒤 저장해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get pillSafetyNotice => isEnglish
      ? 'A pill photo cannot determine your prescribed dose or duration. The values below are placeholders. Check the prescription or package before saving.'
      : '알약 사진만으로 실제 복용량과 기간을 알 수 없습니다. 아래 값은 임시 기본값이므로 처방전이나 약 봉투를 확인한 뒤 저장해주세요.';
  // 함수이름: editTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보 수정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get editTitle => isEnglish ? 'Edit medication plan' : '복약 정보 수정';
  // 함수이름: medicationName
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  // 함수이름: medicationNameRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름을 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  // 함수이름: startDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시작일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get startDate => isEnglish ? 'Start date' : '복용 시작일';
  // 함수이름: dosage
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 복용량" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosage => isEnglish ? 'Dose per intake' : '1회 복용량';
  // 함수이름: dosageHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "예: 1정, 0.5정, 1포" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosageHint => isEnglish ? 'e.g. 1 tablet' : '예: 1정, 0.5정, 1포';
  // 함수이름: dosageRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 복용량을 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosageRequired =>
      isEnglish ? 'Enter the dose per intake.' : '1회 복용량을 입력해주세요.';
  // 함수이름: dailyFrequency
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 복용 횟수" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dailyFrequency => isEnglish ? 'Times per day' : '1일 복용 횟수';
  // 함수이름: duration
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 기간(일)" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get duration => isEnglish ? 'Duration (days)' : '복용 기간(일)';
  // 함수이름: scheduleSlots
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시간대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSlots => isEnglish ? 'Medication times' : '복용 시간대';
  // 함수이름: invalidDuration
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 기간은 1일부터 3650일 사이로 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidDuration => isEnglish
      ? 'Enter a duration between 1 and 3650 days.'
      : '복용 기간은 1일부터 3650일 사이로 입력해주세요.';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';
  // 함수이름: apply
  // 함수역할: 현재 언어와 입력값에 맞춰 "Apply" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get apply => isEnglish ? 'Apply' : '적용';
  // 함수이름: edit
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보 수정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get edit => isEnglish ? 'Edit medication plan' : '복약 정보 수정';
  // 함수이름: reviewNeeded
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인 필요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get reviewNeeded => isEnglish ? 'Review needed' : '확인 필요';
  // 함수이름: confirmAndAnalyze
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인 후 분석하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get confirmAndAnalyze =>
      isEnglish ? 'Confirm and analyze' : '확인 후 분석하기';
  // 함수이름: confirmAndSave
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인하고 저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get confirmAndSave => isEnglish ? 'Confirm and save' : '확인하고 저장하기';

  // 함수이름: frequencyValue
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count회" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String frequencyValue(int count) => isEnglish ? '$count times' : '$count회';
  // 함수이름: durationValue
  // 함수역할: 현재 언어와 입력값에 맞춰 "$days일" 문구를 제공한다.
  // 매개변수:
  // - days (int): 복용 기간의 일수 또는 이를 표현한 원본 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String durationValue(int days) => isEnglish ? '$days days' : '$days일';
  // 함수이름: incompleteSchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "$medicationName의 시작일, 복용량, 횟수, 기간과 시간대를 모두 확인해주세요." 문구를 제공한다.
  // 매개변수:
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String incompleteSchedule(String medicationName) => isEnglish
      ? 'Review all required values for $medicationName.'
      : '$medicationName의 시작일, 복용량, 횟수, 기간과 시간대를 모두 확인해주세요.';
  // 함수이름: scheduleSlotCountMismatch
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 $frequency회에 맞게 복용 시간대를 $frequency개 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - frequency (int): 하루 복용 횟수.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String scheduleSlotCountMismatch(int frequency) => isEnglish
      ? 'Select $frequency medication time(s).'
      : '1일 $frequency회에 맞게 복용 시간대를 $frequency개 선택해주세요.';

  // 함수이름: slotLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotLabel(String slotKey) {
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => slotKey,
    };
  }
}
