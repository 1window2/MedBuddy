part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_list_widgets.dart
// 역할: 저장 약품 정렬, 날짜·복용기간 표시 및 상세·사진 진입을 제공한다.

// Class Name: _SavedMedicationNameRow
// Role: Saved medication list row with separate image and guide actions.
// Responsibilities: Opens guidance from the row and enlarges photos separately; selection mode instead toggles selection and blocks both detail actions.
// Attributes: medication: row data; text: labels; showRegisteredDate: date visibility; isSelectionMode/isSelected: selection state; enabled: interaction allowed outside deletion; onSelectionChanged/onGuideRequested/onImageRequested: row commands.
class _SavedMedicationNameRow extends StatelessWidget {
  final bool showRegisteredDate;
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final bool isSelectionMode;
  final bool enabled;
  final bool isSelected;
  final void Function(bool selected) onSelectionChanged;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;
  final ValueChanged<MedicationRegimenAction> onRegimenRequested;

  // 함수이름: _SavedMedicationNameRow
  // 함수역할: 저장 약의 날짜·이름·사진과 상세 조회, 선택 또는 복약 변경 동작을 연결한다.
  // 매개변수:
  // - showRegisteredDate (bool): 처방 날짜 외에 등록 날짜도 표시할지 여부.
  // - medication (MedicationDetail): 약품 정보와 복약 변경·중단 상태.
  // - text (_SavedMedicationText): 날짜·상태·동작에 사용할 언어별 문구.
  // - isSelectionMode, isSelected (bool): 삭제 선택 모드와 이 약의 선택 상태.
  // - enabled (bool): 삭제 중이 아니어서 행을 조작할 수 있는지 여부.
  // - onSelectionChanged (void Function(bool)): 선택 모드에서 바뀐 선택 여부를 전달할 콜백.
  // - onGuideRequested, onImageRequested (VoidCallback): 일반 모드에서 상세 안내와 사진 확대를 여는 콜백.
  // - onRegimenRequested (ValueChanged<MedicationRegimenAction>): 일반 모드에서 유효한 저장 ID가 있고 중단일이 설정되지 않은 약품의 복약 변경·중단 메뉴 선택을 전달할 콜백.
  // 반환값: 저장 약 한 행. 생성 시 콜백을 실행하지 않는다.
  const _SavedMedicationNameRow({
    required this.showRegisteredDate,
    required this.medication,
    required this.text,
    required this.isSelectionMode,
    required this.enabled,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
    required this.onRegimenRequested,
  });

  // Function Name: build
  // Description: Lays out the medication photo, name, dates and navigation indicator, switching row interaction to selection when requested.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final interactive = enabled && !isSelectionMode;
    // 저장되지 않은 항목(id 없음)은 체크박스와 같은 규칙으로 선택하지 않는다.
    final selectable = enabled && isSelectionMode && (medication.id ?? 0) > 0;
    final displayName = medication.itemName.trim().isEmpty
        ? text.noInformation
        : medication.itemName.trim();
    // 매일 복용하지 않는 약은 쉬는 날 오늘 일정에 없으므로 다음 복용일을 함께 알려준다.
    final today = MedicationHistoryDates.today(DateTime.now());
    final nextDoseDay = medication.nextDoseDayFrom(today);
    // Function Name: calendarDay
    // Description: Normalizes calendar fields without converting time zones so UTC and local date-only values compare as the same day.
    // Parameters: value (DateTime): medication or current calendar date.
    // Returns: Local-midnight DateTime with identical year/month/day.
    DateTime calendarDay(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    final localToday = calendarDay(today);
    final stopDate = medication.stoppedOn;
    final stopPending =
        stopDate != null && calendarDay(stopDate).isAfter(localToday);
    final replaced = medication.supersededById != null;
    final statusLabel = stopDate != null
        ? replaced
              ? (stopPending
                    // 서버는 정보 수정과 새 처방 교체 모두 다음 항목을 연결하므로 두 경우에 맞는 '변경'으로 표시한다.
                    ? (text.isEnglish ? 'Change scheduled' : '처방 변경 예정')
                    : (text.isEnglish ? 'Changed' : '처방 변경'))
              : (stopPending
                    ? (text.isEnglish ? 'Stop scheduled' : '복용 중단 예정')
                    : (text.isEnglish ? 'Stopped' : '복용 중단'))
        : medication.medicationEndDate != null &&
              calendarDay(medication.medicationEndDate!).isBefore(localToday)
        ? (text.isEnglish ? 'Course ended' : '복용 종료')
        : null;
    final statusColor = stopPending
        ? MedBuddyColors.reminderAccent
        : replaced
        ? MedBuddyColors.infoBlue
        : stopDate != null
        ? MedBuddyColors.danger
        : MedBuddyColors.textMuted;
    final statusBackground = stopPending
        ? MedBuddyColors.warningSurface
        : replaced
        ? MedBuddyColors.lavenderSurface
        : stopDate != null
        ? MedBuddyColors.dangerSurface
        : MedBuddyColors.surfaceSubtle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: interactive
            ? onGuideRequested
            : selectable
            ? () => onSelectionChanged(!isSelected)
            : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(isSelectionMode ? 6 : 16, 14, 8, 14),
          child: Row(
            children: [
              if (isSelectionMode)
                Checkbox(
                  key: ValueKey('saved-medication-checkbox-${medication.id}'),
                  semanticLabel: medication.itemName,
                  value: isSelected,
                  activeColor: MedBuddyColors.primary,
                  onChanged: selectable
                      ? (value) => onSelectionChanged(value ?? false)
                      : null,
                ),
              MedicationThumbnail(
                imageUrl: medication.imageUrl,
                localImagePath: medication.localImagePath,
                onTap: interactive ? onImageRequested : null,
                tapKey: ValueKey('savedMedicationImage-${medication.id}'),
                missingImageTooltip: text.noImage,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepWordsText(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    if (showRegisteredDate) ...[
                      const SizedBox(height: 4),
                      _MedicationDateLine(
                        label: text.registeredDate,
                        value: _formatMedicationDate(medication.createdDate),
                        fallback: text.noInformation,
                      ),
                    ],
                    if (medication.isAsNeeded)
                      KeepWordsText(
                        text.isEnglish ? 'As needed' : '필요시 복용',
                        key: ValueKey('saved-medication-prn-${medication.id}'),
                        style: const TextStyle(
                          color: MedBuddyColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (statusLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        key: ValueKey(
                          'saved-medication-status-badge-${medication.id}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusBackground,
                          borderRadius: MedBuddyRadii.small,
                        ),
                        child: KeepWordsText(
                          '$statusLabel · ${_formatMedicationDate(stopDate ?? medication.medicationEndDate)}',
                          key: ValueKey(
                            'saved-medication-status-${medication.id}',
                          ),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    _MedicationDateLine(
                      label: text.medicationPeriod,
                      value: _formatMedicationPeriod(medication),
                      fallback: text.noInformation,
                    ),
                    if (nextDoseDay != null) ...[
                      const SizedBox(height: 4),
                      _MedicationDateLine(
                        key: ValueKey(
                          'saved-medication-next-dose-${medication.id}',
                        ),
                        label: text.nextDoseDay,
                        value: text.nextDoseDayValue(nextDoseDay, today),
                        fallback: text.noInformation,
                      ),
                    ],
                  ],
                ),
              ),
              if (!isSelectionMode)
                PopupMenuButton<MedicationRegimenAction>(
                  key: ValueKey('saved-medication-actions-${medication.id}'),
                  tooltip: text.isEnglish ? 'Medication actions' : '약 관리',
                  enabled:
                      interactive &&
                      (medication.id ?? 0) > 0 &&
                      medication.stoppedOn == null,
                  onSelected: onRegimenRequested,
                  itemBuilder: (_) => [
                    for (final action in MedicationRegimenAction.values)
                      PopupMenuItem(
                        value: action,
                        child: KeepWordsText(
                          regimenActionLabel(action, text.isEnglish),
                        ),
                      ),
                  ],
                ),
              if (!isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: interactive
                        ? MedBuddyColors.textSubtle
                        : MedBuddyColors.textLight,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Class Name: _MedicationDateLine
// Role: A labeled medication date.
// Responsibilities: Displays the complete value with a fallback for an absent date and wrapping for large text.
// Attributes: label: date meaning; value: formatted date; fallback: missing-date text.
class _MedicationDateLine extends StatelessWidget {
  final String label;
  final String value;
  final String fallback;

  // Function Name: _MedicationDateLine
  // Description: Stores a date label, value and missing-date fallback.
  // Parameters: key (Key?): identity; label/value/fallback (String): date caption, formatted value and empty replacement.
  // Returns: A _MedicationDateLine.
  const _MedicationDateLine({
    super.key,
    required this.label,
    required this.value,
    required this.fallback,
  });

  // Function Name: build
  // Description: Shows the complete date value or fallback with its label, allowing text to wrap.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? fallback : value.trim();

    return KeepWordsText(
      '$label: $displayValue',
      softWrap: true,
      style: TextStyle(
        color: MedBuddyColors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

// Function Name: _formatMedicationDate
// Description: Formats a date as year-month-day to match review screens.
// Parameters: value (DateTime?): date to display.
// Returns: A zero-padded date, or an empty string for null.
String _formatMedicationDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year}-${_formatTwoDigits(value.month)}-${_formatTwoDigits(value.day)}';
}

// 함수이름: _formatMedicationPeriod
// 함수역할: 처방일부터 복용 종료일까지의 기간을 표시하며 하루 이하는 시작일만, 같은 해에 끝나면 끝 날짜의 연도를 생략한다. 종료일은 일정·알림과 같은 규칙으로 읽어 "8주"를 56일로 계산한다.
// 매개변수:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _formatMedicationPeriod(MedicationDetail medication) {
  final startDate = medication.prescriptionDate;
  if (startDate == null) {
    return '';
  }

  final endDate = medication.medicationEndDate;
  if (endDate == null ||
      !endDate.isAfter(
        DateTime(startDate.year, startDate.month, startDate.day),
      )) {
    return _formatMedicationDate(startDate);
  }

  // 같은 해에 끝나면 끝 날짜의 연도를 생략해 한 줄에 들어가게 한다.
  final endText = endDate.year == startDate.year
      ? '${_formatTwoDigits(endDate.month)}-${_formatTwoDigits(endDate.day)}'
      : _formatMedicationDate(endDate);
  return '${_formatMedicationDate(startDate)} ~ $endText';
}

// 함수이름: _formatTwoDigits
// 함수역할: 숫자 왼쪽을 0으로 채워 최소 두 자리로 표시한다.
// 매개변수:
// - value (int): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _formatTwoDigits(int value) {
  return value.toString().padLeft(2, '0');
}
