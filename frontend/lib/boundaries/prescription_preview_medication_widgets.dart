part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_medication_widgets.dart
// 역할: OCR 약품 표, 수정 대화상자와 화면 문구를 구성한다.

// 열거형명: _MedicationScheduleEditField
// 역할: 사용자가 누른 표 열과 수정 창에서 처음 선택할 입력란을 연결한다.
enum _MedicationScheduleEditField {
  medicationName,
  dosage,
  dailyFrequency,
  totalDays,
  prescriptionDate,
  scheduleSlots,
}

// 타입명: _MedicationTableEditCallback
// 역할: 표에서 선택한 행, 복약 일정과 수정할 필드를 화면 상태에 전달한다.
typedef _MedicationTableEditCallback =
    void Function(
      int scheduleIndex,
      MedicationSchedule medicationSchedule,
      _MedicationScheduleEditField initialField,
    );

// 클래스명: _PreviewMedicationTable
// 역할: OCR로 인식한 모든 복약 정보를 가로로 이동할 수 있는 단일 표로 보여준다.
// 주요 책임:
// - 세로 화면에서도 모든 열을 확인할 수 있도록 표에 가로 스크롤을 제공한다.
// - 각 값 셀을 누르면 해당 입력란이 선택된 수정 창을 연다.
// - 수정 가능 여부와 약명 보정 상태를 화면에서 바로 알아볼 수 있게 한다.
class _PreviewMedicationTable extends StatelessWidget {
  static const double _tableWidth = 1010;

  final List<MedicationSchedule> medicationScheduleList;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final ScrollController scrollController;
  final _MedicationTableEditCallback onEditRequested;

  const _PreviewMedicationTable({
    required this.medicationScheduleList,
    required this.previewText,
    required this.userSetting,
    required this.scrollController,
    required this.onEditRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note_rounded,
              size: 20 * scale,
              color: MedBuddyColors.primaryDark,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                previewText.tableEditGuide,
                style: TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: MedBuddyColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                key: const Key('ocr-medication-table-scroll'),
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 11),
                child: SizedBox(
                  width: _tableWidth,
                  child: Table(
                    key: const Key('ocr-medication-table'),
                    border: const TableBorder(
                      horizontalInside: BorderSide(
                        color: MedBuddyColors.outline,
                      ),
                      verticalInside: BorderSide(color: MedBuddyColors.outline),
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(240),
                      1: FixedColumnWidth(150),
                      2: FixedColumnWidth(150),
                      3: FixedColumnWidth(130),
                      4: FixedColumnWidth(160),
                      5: FixedColumnWidth(180),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      _buildHeaderRow(scale),
                      for (
                        int index = 0;
                        index < medicationScheduleList.length;
                        index++
                      )
                        _buildMedicationRow(
                          index,
                          medicationScheduleList[index],
                          scale,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  TableRow _buildHeaderRow(double scale) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEAF8F3)),
      children: [
        _TableHeaderCell(label: previewText.medicationName, scale: scale),
        _TableHeaderCell(label: previewText.dosage, scale: scale),
        _TableHeaderCell(label: previewText.dailyFrequency, scale: scale),
        _TableHeaderCell(label: previewText.totalDays, scale: scale),
        _TableHeaderCell(label: previewText.medicationStartDate, scale: scale),
        _TableHeaderCell(label: previewText.scheduleSlots, scale: scale),
      ],
    );
  }

  TableRow _buildMedicationRow(
    int scheduleIndex,
    MedicationSchedule schedule,
    double scale,
  ) {
    return TableRow(
      children: [
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-name'),
          semanticsLabel: previewText.editCell(
            previewText.medicationName,
            schedule.displayNameForLanguage(previewText.language),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.medicationName,
          ),
          child: _MedicationNameTableValue(
            schedule: schedule,
            previewText: previewText,
            scale: scale,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-dosage'),
          semanticsLabel: previewText.editCell(
            previewText.dosage,
            schedule.dosageLabelForLanguage(previewText.language),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.dosage,
          ),
          child: _TableValueText(
            value: schedule.dosageLabelForLanguage(previewText.language),
            scale: scale,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-frequency'),
          semanticsLabel: previewText.editCell(
            previewText.dailyFrequency,
            schedule.dailyFrequencyLabelForLanguage(previewText.language),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.dailyFrequency,
          ),
          child: _TableValueText(
            value: schedule.dailyFrequencyLabelForLanguage(
              previewText.language,
            ),
            scale: scale,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-days'),
          semanticsLabel: previewText.editCell(
            previewText.totalDays,
            schedule.durationLabelForLanguage(previewText.language),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.totalDays,
          ),
          child: _TableValueText(
            value: schedule.durationLabelForLanguage(previewText.language),
            scale: scale,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-date'),
          semanticsLabel: previewText.editCell(
            previewText.medicationStartDate,
            previewText.dateValue(schedule.prescriptionDate),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.prescriptionDate,
          ),
          child: _TableValueText(
            value: previewText.dateValue(schedule.prescriptionDate),
            scale: scale,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-slots'),
          semanticsLabel: previewText.editCell(
            previewText.scheduleSlots,
            previewText.slotSummary(schedule.slotKeys),
          ),
          onTap: () => onEditRequested(
            scheduleIndex,
            schedule,
            _MedicationScheduleEditField.scheduleSlots,
          ),
          child: _TableValueText(
            value: previewText.slotSummary(schedule.slotKeys),
            scale: scale,
          ),
        ),
      ],
    );
  }
}

// 클래스명: _TableHeaderCell
// 역할: 복약 정보 표의 열 이름을 일관된 크기와 색상으로 표시한다.
class _TableHeaderCell extends StatelessWidget {
  final String label;
  final double scale;

  const _TableHeaderCell({required this.label, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        maxLines: 2,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 13 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _EditableMedicationCell
// 역할: 복약 정보 값을 수정 가능한 표 셀과 접근성 버튼으로 제공한다.
class _EditableMedicationCell extends StatelessWidget {
  final Key cellKey;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  const _EditableMedicationCell({
    required this.cellKey,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        key: cellKey,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: child,
        ),
      ),
    );
  }
}

// 클래스명: _TableValueText
// 역할: 표 안의 일반 복약 정보 값을 큰 글씨에서도 넘치지 않게 표시한다.
class _TableValueText extends StatelessWidget {
  final String value;
  final double scale;

  const _TableValueText({required this.value, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 14 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

// 클래스명: _MedicationNameTableValue
// 역할: 약명, 보정 상태와 최초 OCR 약명을 하나의 표 셀에 표시한다.
class _MedicationNameTableValue extends StatelessWidget {
  final MedicationSchedule schedule;
  final _PreviewText previewText;
  final double scale;

  const _MedicationNameTableValue({
    required this.schedule,
    required this.previewText,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final correctionBadge = schedule.isNameConfirmed
        ? _CorrectionBadge(label: previewText.confirmed, scale: scale)
        : schedule.hasNameCorrection
        ? _CorrectionBadge(label: previewText.corrected, scale: scale)
        : schedule.isNameReviewRequired
        ? _CorrectionBadge(
            label: previewText.reviewNeeded,
            scale: scale,
            isWarning: true,
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                schedule.displayNameForLanguage(previewText.language),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (correctionBadge != null) ...[
              const SizedBox(width: 6),
              correctionBadge,
            ],
          ],
        ),
        if (schedule.hasNameCorrection) ...[
          const SizedBox(height: 4),
          Text(
            previewText.correctedFrom(schedule.rawMedicationName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MedBuddyColors.textLight,
              fontSize: 11 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _CorrectionBadge extends StatelessWidget {
  final String label;
  final double scale;
  final bool isWarning;

  const _CorrectionBadge({
    required this.label,
    required this.scale,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF4D6) : const Color(0xFFE6F7F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isWarning
              ? const Color(0xFF9A6700)
              : MedBuddyColors.primaryDark,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _MedicationScheduleEditDialog
// 역할: OCR로 인식된 약명과 복약 정보를 사용자가 수정하는 입력 창을 제공한다.
// 주요 책임:
// - 약명, 조제일자, 투약량, 횟수, 투약일의 현재 값을 입력란에 표시한다.
// - 실제 복약할 아침·점심·저녁·취침 전 시간대를 사용자가 확인하게 한다.
// - 입력 형식을 검증한 뒤 변경된 복약 일정 객체를 반환한다.
class _MedicationScheduleEditDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final _MedicationScheduleEditField initialField;

  const _MedicationScheduleEditDialog({
    required this.medicationSchedule,
    required this.previewText,
    required this.userSetting,
    required this.initialField,
  });

  @override
  State<_MedicationScheduleEditDialog> createState() =>
      _MedicationScheduleEditDialogState();
}

// 클래스명: _MedicationScheduleEditDialogState
// 역할: OCR 수정 입력값과 유효성 검사 상태를 대화상자의 생명주기에 맞춰 관리한다.
// 주요 책임:
// - 입력 컨트롤러를 생성하고 화면이 닫힐 때 안전하게 정리한다.
// - 유효한 입력만 MedicationSchedule로 변환해 호출 화면에 반환한다.
class _MedicationScheduleEditDialogState
    extends State<_MedicationScheduleEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _daysController;
  late final TextEditingController _prescriptionDateController;
  late Set<String> _selectedSlotKeys;
  bool _showSlotValidationError = false;
  bool _restoreOriginalName = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.medicationSchedule.medicationName,
    );
    _dosageController = TextEditingController(
      text: widget.medicationSchedule.dosage,
    );
    _frequencyController = TextEditingController(
      text: widget.medicationSchedule.intakeTime,
    );
    _daysController = TextEditingController(
      text: widget.medicationSchedule.medicationTime <= 0
          ? ''
          : widget.medicationSchedule.medicationTime.toString(),
    );
    _prescriptionDateController = TextEditingController(
      text: _formatDate(
        widget.medicationSchedule.prescriptionDate ?? DateTime.now(),
      ),
    );
    _selectedSlotKeys = widget.medicationSchedule.slotKeys.toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _daysController.dispose();
    _prescriptionDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.previewText;
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
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('ocr-edit-name'),
                controller: _nameController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.medicationName,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.medicationName),
                validator: (value) => value == null || value.trim().isEmpty
                    ? text.medicationNameRequired
                    : null,
              ),
              if (_hasRestorableOriginalName)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('ocr-restore-original-name'),
                    onPressed: _restoreOriginalMedicationName,
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(text.restoreOriginalName),
                  ),
                ),
              TextFormField(
                key: const Key('ocr-edit-prescription-date'),
                controller: _prescriptionDateController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.prescriptionDate,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: text.prescriptionDate,
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: text.chooseDate,
                    onPressed: _selectPrescriptionDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                validator: _validatePrescriptionDate,
              ),
              TextFormField(
                key: const Key('ocr-edit-dosage'),
                controller: _dosageController,
                autofocus:
                    widget.initialField == _MedicationScheduleEditField.dosage,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dosage),
              ),
              TextFormField(
                key: const Key('ocr-edit-frequency'),
                controller: _frequencyController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.dailyFrequency,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dailyFrequency),
              ),
              TextFormField(
                key: const Key('ocr-edit-days'),
                controller: _daysController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.totalDays,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: text.totalDays),
                validator: _validateMedicationDays,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text.scheduleSlots,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Focus(
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.scheduleSlots,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slotKey in medicationScheduleSlotKeys)
                      FilterChip(
                        key: Key('ocr-edit-slot-$slotKey'),
                        label: Text(text.slotLabel(slotKey)),
                        selected: _selectedSlotKeys.contains(slotKey),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedSlotKeys.add(slotKey);
                            } else {
                              _selectedSlotKeys.remove(slotKey);
                            }
                            _showSlotValidationError = false;
                          });
                        },
                      ),
                  ],
                ),
              ),
              if (_showSlotValidationError) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.scheduleSlotRequired,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12 * scale,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ocr-edit-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          key: const Key('ocr-edit-save'),
          onPressed: _submit,
          child: Text(text.apply),
        ),
      ],
    );
  }

  // 함수이름: _validateMedicationDays
  // 함수역할:
  // - 총 투약일 입력값이 비어 있거나 허용 범위의 양의 정수인지 확인한다.
  // 매개변수:
  // - value: 사용자가 입력한 총 투약일 문자열
  // 반환값:
  // - 유효하면 null, 유효하지 않으면 화면에 표시할 오류 문구
  String? _validateMedicationDays(String? value) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      return null;
    }
    final medicationDays = int.tryParse(trimmedValue);
    if (medicationDays == null ||
        medicationDays <= 0 ||
        medicationDays > 3650) {
      return widget.previewText.invalidTotalDays;
    }
    return null;
  }

  // 함수명: _validatePrescriptionDate
  // 역할:
  // - 조제일자가 실제 달력에 존재하고 허용 범위 안의 날짜인지 확인한다.
  String? _validatePrescriptionDate(String? value) {
    final parsedDate = _parseDate(value?.trim() ?? '');
    if (parsedDate == null) {
      return widget.previewText.invalidPrescriptionDate;
    }
    if (parsedDate.isBefore(_minimumPrescriptionDate) ||
        parsedDate.isAfter(_maximumPrescriptionDate)) {
      return widget.previewText.prescriptionDateOutOfRange;
    }
    return null;
  }

  DateTime get _minimumPrescriptionDate => DateTime(2000);

  DateTime get _maximumPrescriptionDate {
    final maximumDate = DateTime.now().add(const Duration(days: 365));
    return DateTime(maximumDate.year, maximumDate.month, maximumDate.day);
  }

  // 함수명: _selectPrescriptionDate
  // 역할:
  // - 달력에서 조제일자를 선택하고 직접 입력 필드에 반영한다.
  Future<void> _selectPrescriptionDate() async {
    final parsedInitialDate =
        _parseDate(_prescriptionDateController.text.trim()) ?? DateTime.now();
    final initialDate = parsedInitialDate.isBefore(_minimumPrescriptionDate)
        ? _minimumPrescriptionDate
        : parsedInitialDate.isAfter(_maximumPrescriptionDate)
        ? _maximumPrescriptionDate
        : parsedInitialDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _minimumPrescriptionDate,
      lastDate: _maximumPrescriptionDate,
    );
    if (!mounted || selectedDate == null) {
      return;
    }
    setState(() {
      _prescriptionDateController.text = _formatDate(selectedDate);
    });
  }

  // 함수이름: _submit
  // 함수역할:
  // - 수정 입력값을 검증하고 변경된 복약 일정 객체를 호출 화면으로 반환한다.
  // 반환값:
  // - 없음
  void _submit() {
    final hasSelectedSlot = _selectedSlotKeys.isNotEmpty;
    if (!hasSelectedSlot) {
      setState(() => _showSlotValidationError = true);
    }
    if (!(_formKey.currentState?.validate() ?? false) || !hasSelectedSlot) {
      return;
    }

    final medicationName = _nameController.text.trim();
    final originalMedicationName = widget.medicationSchedule.rawMedicationName
        .trim();
    final restoresOriginalName =
        _restoreOriginalName && medicationName == originalMedicationName;

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: medicationName,
        dosage: _dosageController.text.trim(),
        intakeTime: _frequencyController.text.trim(),
        medicationTime: int.tryParse(_daysController.text.trim()) ?? 0,
        prescriptionDate: _parseDate(_prescriptionDateController.text.trim()),
        scheduleSlotKeys: medicationScheduleSlotKeys
            .where(_selectedSlotKeys.contains)
            .toList(growable: false),
        rawMedicationName: restoresOriginalName
            ? ''
            : widget.medicationSchedule.rawMedicationName,
        nameConfidence: restoresOriginalName ? 0 : 1,
        nameCorrectionSource: restoresOriginalName
            ? 'ocr_reset'
            : 'user_review',
      ),
    );
  }

  bool get _hasRestorableOriginalName {
    final originalName = widget.medicationSchedule.rawMedicationName.trim();
    return originalName.isNotEmpty &&
        originalName != widget.medicationSchedule.medicationName.trim();
  }

  // 함수명: _restoreOriginalMedicationName
  // 역할:
  // - 자동 보정 또는 사용자 수정 전의 최초 OCR 약명으로 입력값을 되돌린다.
  void _restoreOriginalMedicationName() {
    setState(() {
      _nameController.text = widget.medicationSchedule.rawMedicationName.trim();
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
      _restoreOriginalName = true;
    });
  }

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsedDate = DateTime(year, month, day);
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      return null;
    }
    return parsedDate;
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class _PreviewText {
  final String language;

  const _PreviewText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get analyze => isEnglish ? 'Analyze' : '분석하기';
  String get reviewBeforeAnalyze =>
      isEnglish ? 'Review and analyze' : '검토 후 분석하기';
  String get confirmAndAnalyze =>
      isEnglish ? 'Confirm and analyze' : '검토 완료 및 분석하기';
  String get noInformation => isEnglish ? 'No info' : '정보 없음';
  String get corrected => isEnglish ? 'Corrected' : '보정';
  String get confirmed => isEnglish ? 'Confirmed' : '확인 완료';
  String get reviewNeeded => isEnglish ? 'Review' : '검토 필요';
  String get edit => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get editTitle => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  String get dosage => isEnglish ? 'Dose per intake' : '1회 투약량';
  String get dailyFrequency => isEnglish ? 'Daily frequency' : '1일 횟수';
  String get totalDays => isEnglish ? 'Total days' : '총 투약일';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get apply => isEnglish ? 'Apply' : '적용';
  String get restoreOriginalName =>
      isEnglish ? 'Restore the original OCR name' : '최초 인식 약명으로 되돌리기';
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  String get prescriptionDate => isEnglish ? 'Dispensing date' : '조제일자';
  String get chooseDate => isEnglish ? 'Choose date' : '날짜 선택';
  String get invalidPrescriptionDate => isEnglish
      ? 'Enter a valid date as YYYY-MM-DD.'
      : '올바른 날짜를 YYYY-MM-DD 형식으로 입력해주세요.';
  String get prescriptionDateOutOfRange => isEnglish
      ? 'Enter a date from 2000-01-01 through one year from today.'
      : '2000-01-01부터 오늘 기준 1년 이내 날짜를 입력해주세요.';
  String get scheduleSlots => isEnglish ? 'Medication times' : '실제 복약 시간대';
  String get scheduleSlotRequired => isEnglish
      ? 'Select at least one medication time.'
      : '복약 시간대를 하나 이상 선택해주세요.';
  String get invalidTotalDays => isEnglish
      ? 'Enter a number between 1 and 3650.'
      : '1일 이상 3650일 이하의 숫자를 입력해주세요.';
  String get medicationStartDate => isEnglish ? 'Start date' : '복용 시작일';
  String get tableEditGuide => isEnglish
      ? 'Swipe sideways to see more. Tap any value to edit it.'
      : '표를 옆으로 밀어 더 확인하고, 수정할 값은 바로 눌러주세요.';
  String get tableScrollHint => isEnglish
      ? 'Swipe sideways to review all medication details.'
      : '표를 옆으로 밀어 모든 복약 정보를 확인해보세요.';

  String slotLabel(String slotKey) {
    if (isEnglish) {
      return switch (slotKey) {
        'morning' => 'Morning',
        'lunch' => 'Lunch',
        'evening' => 'Evening',
        'bedtime' => 'Bedtime',
        _ => slotKey,
      };
    }
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => slotKey,
    };
  }

  String get recognizedRegionGuide => isEnglish
      ? 'Green boxes show medication information. Gray areas mask personal data.'
      : '초록색은 약품 정보 인식 영역이며 회색은 개인정보 마스킹 영역입니다.';
  String get imageUnavailable =>
      isEnglish ? 'Image preview unavailable' : '이미지를 표시할 수 없습니다.';
  String get regionUnavailable => isEnglish
      ? 'Region coordinates are unavailable. Review the list below.'
      : '인식 위치 정보가 없어 아래 추출 목록을 확인해주세요.';
  String get privacyNotice => isEnglish
      ? 'The original image stays on this device. Only OCR text with detected '
            'personal identifiers removed is sent for medication analysis.'
      : '원본 이미지는 이 기기에만 남습니다. 기기에서 OCR한 뒤 감지된 개인정보를 제거한 '
            '복약 관련 텍스트만 분석 서버로 전송합니다.';
  String get sensitiveMaskLabel =>
      isEnglish ? 'Personal information masked' : '개인정보 마스킹';
  String get openImagePreview => isEnglish ? 'Open image preview' : '이미지 크게 보기';
  String get expandedImageTitle =>
      isEnglish ? 'Recognized image' : '인식 영역 상세보기';
  String get close => isEnglish ? 'Close' : '닫기';

  String editCell(String fieldLabel, String value) {
    return isEnglish
        ? 'Edit $fieldLabel. Current value: $value'
        : '$fieldLabel 수정. 현재 값: $value';
  }

  String dateValue(DateTime? date) {
    if (date == null) {
      return noInformation;
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String slotSummary(List<String> slotKeys) {
    if (slotKeys.isEmpty) {
      return noInformation;
    }
    return slotKeys.map(slotLabel).join(', ');
  }

  String correctedFrom(String rawName) {
    return isEnglish ? 'OCR: $rawName' : 'OCR 원문: $rawName';
  }

  String title(DateTime date) {
    if (isEnglish) {
      return '${date.month}/${date.day} Prescription';
    }

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday) 처방 내역';
  }
}
