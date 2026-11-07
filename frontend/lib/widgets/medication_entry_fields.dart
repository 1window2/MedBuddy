// 파일명: medication_entry_fields.dart
// 역할: 약 직접 등록과 처방 변경에서 공유하는 이름·용량·기간·주기·시간대 입력을 제공한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_dose_rhythm.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';

const medicationEntryDoseUnits = ['정', '캡슐', '포', 'mL', '방울'];

// 직접 등록과 처방 변경은 입력 요소만 공유하고 저장·기록 보존 흐름은 분리한다.
// 클래스명: MedicationEntrySectionTitle
// 역할: 구역 제목과 선택적 보조 문구를 줄바꿈해 표시한다.
// 주요 책임: 좁은 너비에서도 보조 문구가 제목을 가리지 않도록 배치한다.
// 속성: title (String): 제목; optional (String?): 부가 문구.
class MedicationEntrySectionTitle extends StatelessWidget {
  final String title;
  final String? optional;

  // 함수이름: MedicationEntrySectionTitle
  // 함수역할: 제목과 선택적 보조 문구를 보관한다.
  // 매개변수: key (Key?): 식별 키; title (String): 제목; optional (String?): 부가 문구.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntrySectionTitle 위젯.
  const MedicationEntrySectionTitle({
    super.key,
    required this.title,
    this.optional,
  });

  // 함수이름: build
  // 함수역할: 두 문구를 공통 스타일의 Wrap으로 표시한다. optional이 null일 때만 보조 문구를 제외한다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(title, style: MedBuddyTextStyles.formSectionTitle),
      if (optional != null) ...[
        Text(
          optional!,
          style: const TextStyle(
            color: MedBuddyColors.textLight,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

// 클래스명: MedicationEntryNameField
// 역할: 약 이름 입력과 검증을 호출자의 폼에 연결한다.
// 주요 책임: 제목·선택 동작·200자 제한 입력을 공통으로 구성한다.
// 속성: fieldKey: 입력 키; controller: 외부 소유 컨트롤러; enabled/showCounter: 편집·글자수 표시; title/hint: 문구; validator: 오류 검사; titleAction: 선택 동작.
class MedicationEntryNameField extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final String title;
  final String hint;
  final String? Function(String?) validator;
  final bool showCounter;
  final Widget? titleAction;

  // 함수이름: MedicationEntryNameField
  // 함수역할: 이름 입력 상태와 검증 함수를 보관하며 컨트롤러 수명은 호출자에게 맡긴다.
  // 매개변수: key/fieldKey: 식별자; controller: 약 이름; enabled/showCounter: 편집·글자수 표시; title/hint: 문구; validator: 오류 문자열 또는 null 반환 함수; titleAction: 선택 위젯.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntryNameField 위젯.
  const MedicationEntryNameField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.title,
    required this.hint,
    required this.validator,
    this.showCounter = false,
    this.titleAction,
  });

  // 함수이름: build
  // 함수역할: 제목 옆 동작과 200자 제한 입력창을 표시하고 검증은 validator에 위임한다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: MedicationEntrySectionTitle(title: title)),
          ?titleAction,
        ],
      ),
      const SizedBox(height: 10),
      TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        maxLength: 200,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          counterText: showCounter ? null : '',
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    ],
  );
}

// 클래스명: MedicationEntryDoseFields
// 역할: 용량·단위 또는 분해할 수 없는 기존 복용량 문구를 편집한다.
// 주요 책임: 단위가 있을 때만 숫자 제한과 단위 선택을 적용한다.
// 속성: keyPrefix: 입력 키; controller: 용량; enabled: 편집 여부; title/amountLabel/unitLabel: 문구; unit (String?): 단위; unitText/onUnitChanged/validator: 표시·변경·검증 함수.
class MedicationEntryDoseFields extends StatelessWidget {
  final String keyPrefix;
  final TextEditingController controller;
  final bool enabled;
  final String title;
  final String amountLabel;
  final String unitLabel;
  final String? unit;
  final String Function(String) unitText;
  final ValueChanged<String?> onUnitChanged;
  final String? Function(String?) validator;

  // 함수이름: MedicationEntryDoseFields
  // 함수역할: 용량 입력과 단위 표시·변경·검증 동작을 연결한다.
  // 매개변수: key/keyPrefix: 식별자; controller: 용량; enabled: 편집 여부; title/amountLabel/unitLabel: 문구; unit: null이면 자유 입력; unitText/onUnitChanged/validator: 단위 표시·변경·용량 검사.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntryDoseFields 위젯.
  const MedicationEntryDoseFields({
    super.key,
    required this.keyPrefix,
    required this.controller,
    required this.enabled,
    required this.title,
    required this.amountLabel,
    required this.unitLabel,
    required this.unit,
    required this.unitText,
    required this.onUnitChanged,
    required this.validator,
  });

  // 함수이름: build
  // 함수역할: 단위가 없으면 300자 자유 입력, 있으면 숫자·점 8자 입력과 지원 단위 선택을 표시한다. 최종 값 검사는 validator가 맡는다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) {
    // 분리할 수 없는 예전 복용량은 숫자나 기본 단위로 강제 변환하지 않는다.
    final amount = TextFormField(
      key: Key('$keyPrefix-dosage'),
      controller: controller,
      enabled: enabled,
      maxLength: unit == null ? 300 : null,
      keyboardType: unit == null
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: unit == null
          ? null
          : [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(8),
            ],
      decoration: InputDecoration(
        labelText: unit == null ? null : amountLabel,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicationEntrySectionTitle(title: title),
        const SizedBox(height: 10),
        if (unit == null)
          amount
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: amount),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('$keyPrefix-unit'),
                  isExpanded: true,
                  initialValue: unit,
                  decoration: InputDecoration(
                    labelText: unitLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in medicationEntryDoseUnits)
                      DropdownMenuItem(
                        value: value,
                        child: Text(unitText(value)),
                      ),
                  ],
                  onChanged: enabled ? onUnitChanged : null,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// 클래스명: MedicationEntryDateButton
// 역할: 날짜 항목명과 현재 값을 하나의 버튼에 표시한다.
// 주요 책임: 최소 터치 높이와 두 줄 표시를 제공하고 날짜 선택은 외부에 맡긴다.
// 속성: buttonKey (Key?): 버튼 키; label/value (String): 항목명·값; onPressed (VoidCallback?): 선택 동작.
class MedicationEntryDateButton extends StatelessWidget {
  final Key? buttonKey;
  final String label;
  final String value;
  final VoidCallback? onPressed;

  // 함수이름: MedicationEntryDateButton
  // 함수역할: 날짜 문구와 선택 동작을 연결하며 날짜를 직접 파싱하지 않는다.
  // 매개변수: key/buttonKey (Key?): 식별자; label/value (String): 문구; onPressed (VoidCallback?): null이면 비활성.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntryDateButton 위젯.
  const MedicationEntryDateButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 항목명과 값을 가운데 정렬한 최소 높이 72px 테두리 버튼을 만든다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: buttonKey,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      foregroundColor: MedBuddyColors.textStrong,
      side: const BorderSide(color: MedBuddyColors.outline, width: 1.5),
    ),
    child: Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

// 클래스명: MedicationEntryPeriodFields
// 역할: 복약 시작·종료 날짜 입력과 기간 요약을 배치한다.
// 주요 책임: 큰 글씨의 좁은 화면에서 날짜 버튼을 세로로 바꾼다.
// 속성: title/summary (String): 제목·요약; startButton/endButton (Widget): 호출자 소유 날짜 선택 버튼.
class MedicationEntryPeriodFields extends StatelessWidget {
  final String title;
  final Widget startButton;
  final Widget endButton;
  final String summary;

  // 함수이름: MedicationEntryPeriodFields
  // 함수역할: 날짜 버튼과 기간 설명을 공통 레이아웃에 연결한다.
  // 매개변수: key (Key?): 식별 키; title/summary (String): 문구; startButton/endButton (Widget): 날짜 버튼.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntryPeriodFields 위젯.
  const MedicationEntryPeriodFields({
    super.key,
    required this.title,
    required this.startButton,
    required this.endButton,
    required this.summary,
  });

  // 함수이름: build
  // 함수역할: 340px 미만 너비에서 16px 기준 확대 글자가 24px를 넘으면 날짜를 세로로, 나머지는 가로로 표시한다. 날짜 범위를 검증하지 않는다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MedicationEntrySectionTitle(title: title),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 340 &&
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [startButton, const SizedBox(height: 8), endButton],
            );
          }
          return Row(
            children: [
              Expanded(child: startButton),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(child: endButton),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      Text(
        summary,
        style: const TextStyle(
          color: MedBuddyColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

// 클래스명: MedicationEntryCycleChoices
// 역할: 복약 주기를 단일 선택 칩으로 표시한다.
// 주요 책임: 기본·추가·현재 주기를 중복 제거하고 선택 의도를 상위 폼에 전달한다.
// 속성: keyPrefix/value (String): 칩 키·현재 값; label: 표시 함수; onChanged: 선택 콜백; extraChoices (List<String>): 추가 항목.
class MedicationEntryCycleChoices extends StatelessWidget {
  final String keyPrefix;
  final String value;
  final String Function(String) label;
  final ValueChanged<String>? onChanged;
  final List<String> extraChoices;

  // 함수이름: MedicationEntryCycleChoices
  // 함수역할: 현재 주기와 표시·변경 동작을 보관한다.
  // 매개변수: key/keyPrefix: 식별자; value (String): 현재 주기; label: 표시 변환; onChanged (ValueChanged<String>?): null이면 비활성; extraChoices (List<String>): 추가 선택.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntryCycleChoices 위젯.
  const MedicationEntryCycleChoices({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.label,
    required this.onChanged,
    this.extraChoices = const [],
  });

  // 함수이름: build
  // 함수역할: 기본 목록 밖의 현재 값도 유지하며 중복 제거한 ChoiceChip을 만든다. 선택한 주기를 콜백에 전달한다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final choice in {...doseDayChoices, ...extraChoices, value})
        ChoiceChip(
          key: Key('$keyPrefix-$choice'),
          label: Text(label(choice)),
          selected: value == choice,
          onSelected: onChanged == null ? null : (_) => onChanged!(choice),
        ),
    ],
  );
}

// 클래스명: MedicationEntrySlotChoices
// 역할: 정의된 복약 시간대를 다중 선택 칩으로 표시한다.
// 주요 책임: 공통 시간대 순서를 유지하고 선택 집합을 직접 수정하지 않는다.
// 속성: keyPrefix (String): 칩 키; values (Set<String>): 선택값; label: 표시 함수; onChanged: 시간대·선택 여부 콜백.
class MedicationEntrySlotChoices extends StatelessWidget {
  final String keyPrefix;
  final Set<String> values;
  final String Function(String) label;
  final void Function(String, bool)? onChanged;

  // 함수이름: MedicationEntrySlotChoices
  // 함수역할: 시간대 집합과 표시·변경 함수를 보관한다.
  // 매개변수: key/keyPrefix: 식별자; values (Set<String>): 선택 시간대; label: 문구 변환; onChanged (void Function(String, bool)?): null이면 비활성.
  // 반환값: 상태와 입력 처리를 호출자에 위임하는 MedicationEntrySlotChoices 위젯.
  const MedicationEntrySlotChoices({
    super.key,
    required this.keyPrefix,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 알려진 시간대만 FilterChip으로 표시하며 탭한 시간대와 새 선택 여부를 전달한다.
  // 매개변수: context (BuildContext) - 현재 폼의 위젯 위치.
  // 반환값: 설정한 상태와 콜백을 반영한 입력 구역 위젯.
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final slot in medicationScheduleSlotKeys)
        FilterChip(
          key: Key('$keyPrefix-$slot'),
          label: Text(label(slot)),
          selected: values.contains(slot),
          onSelected: onChanged == null
              ? null
              : (selected) => onChanged!(slot, selected),
        ),
    ],
  );
}
