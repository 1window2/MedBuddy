part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_medication_widgets.dart
// 역할: OCR 약품 목록, 수정 대화상자, 페이지 표시와 화면 문구를 구성한다.

class _PreviewMedicationPage extends StatelessWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final int firstScheduleIndex;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final MedicationScheduleChangedCallback onEditRequested;

  const _PreviewMedicationPage({
    required this.medicationScheduleList,
    required this.firstScheduleIndex,
    required this.previewText,
    required this.userSetting,
    required this.onEditRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < medicationScheduleList.length; index++) ...[
          _PreviewMedicationRow(
            schedule: medicationScheduleList[index],
            scheduleIndex: firstScheduleIndex + index,
            previewText: previewText,
            userSetting: userSetting,
            onEditRequested: () => onEditRequested(
              firstScheduleIndex + index,
              medicationScheduleList[index],
            ),
          ),
          if (index != medicationScheduleList.length - 1)
            const Divider(height: 22),
        ],
      ],
    );
  }
}

class _PreviewMedicationRow extends StatelessWidget {
  final MedicationSchedule schedule;
  final int scheduleIndex;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final VoidCallback onEditRequested;

  const _PreviewMedicationRow({
    required this.schedule,
    required this.scheduleIndex,
    required this.previewText,
    required this.userSetting,
    required this.onEditRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final frequency = schedule.intakeTime.trim().isEmpty
        ? previewText.noInformation
        : schedule.intakeTime.trim();
    final isUserEdited = schedule.nameCorrectionSource == 'user_edit';
    final needsReview =
        schedule.nameCorrectionSource == 'unverified' ||
        (schedule.nameConfidence > 0 && schedule.nameConfidence < 0.75);
    final correctionBadge = isUserEdited
        ? _CorrectionBadge(label: previewText.userEdited, scale: scale)
        : schedule.hasNameCorrection
        ? _CorrectionBadge(label: previewText.corrected, scale: scale)
        : needsReview
        ? _CorrectionBadge(
            label: previewText.reviewNeeded,
            scale: scale,
            isWarning: true,
          )
        : null;
    final useStackedCorrectionBadge =
        MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final medicationName = Text(
      schedule.displayName,
      maxLines: useStackedCorrectionBadge ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 18 * scale,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (useStackedCorrectionBadge)
                medicationName
              else
                Row(
                  children: [
                    Expanded(child: medicationName),
                    if (correctionBadge != null) ...[
                      const SizedBox(width: 6),
                      correctionBadge,
                    ],
                  ],
                ),
              if (useStackedCorrectionBadge && correctionBadge != null) ...[
                const SizedBox(height: 4),
                correctionBadge,
              ],
              if (schedule.hasNameCorrection) ...[
                const SizedBox(height: 3),
                Text(
                  previewText.correctedFrom(schedule.rawMedicationName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textLight,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 56),
          child: Text(
            frequency,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        IconButton(
          key: Key('ocr-edit-$scheduleIndex'),
          tooltip: previewText.edit,
          onPressed: onEditRequested,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          icon: Icon(
            Icons.edit_outlined,
            size: 20 * scale,
            color: MedBuddyColors.primaryDark,
          ),
        ),
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

  const _MedicationScheduleEditDialog({
    required this.medicationSchedule,
    required this.previewText,
    required this.userSetting,
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
                autofocus: true,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.medicationName),
                validator: (value) => value == null || value.trim().isEmpty
                    ? text.medicationNameRequired
                    : null,
              ),
              TextFormField(
                key: const Key('ocr-edit-prescription-date'),
                controller: _prescriptionDateController,
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
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dosage),
              ),
              TextFormField(
                key: const Key('ocr-edit-frequency'),
                controller: _frequencyController,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dailyFrequency),
              ),
              TextFormField(
                key: const Key('ocr-edit-days'),
                controller: _daysController,
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
              Wrap(
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
  // - 조제일자가 실제 달력에 존재하는 YYYY-MM-DD 형식인지 확인한다.
  String? _validatePrescriptionDate(String? value) {
    return _parseDate(value?.trim() ?? '') == null
        ? widget.previewText.invalidPrescriptionDate
        : null;
  }

  // 함수명: _selectPrescriptionDate
  // 역할:
  // - 달력에서 조제일자를 선택하고 직접 입력 필드에 반영한다.
  Future<void> _selectPrescriptionDate() async {
    final initialDate =
        _parseDate(_prescriptionDateController.text.trim()) ?? DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: _nameController.text.trim(),
        dosage: _dosageController.text.trim(),
        intakeTime: _frequencyController.text.trim(),
        medicationTime: int.tryParse(_daysController.text.trim()) ?? 0,
        prescriptionDate: _parseDate(_prescriptionDateController.text.trim()),
        scheduleSlotKeys: medicationScheduleSlotKeys
            .where(_selectedSlotKeys.contains)
            .toList(growable: false),
      ),
    );
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

class _PreviewDot extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _PreviewDot({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: active ? MedBuddyColors.primary : MedBuddyColors.outline,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PreviewText {
  final String language;

  const _PreviewText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get analyze => isEnglish ? 'Analyze' : '분석하기';
  String get noInformation => isEnglish ? 'No info' : '정보 없음';
  String get corrected => isEnglish ? 'Corrected' : '보정';
  String get userEdited => isEnglish ? 'Edited' : '사용자 수정';
  String get reviewNeeded => isEnglish ? 'Review' : '검토 필요';
  String get edit => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get editTitle => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  String get dosage => isEnglish ? 'Dose per intake' : '1회 투약량';
  String get dailyFrequency => isEnglish ? 'Daily frequency' : '1일 횟수';
  String get totalDays => isEnglish ? 'Total days' : '총 투약일';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get apply => isEnglish ? 'Apply' : '적용';
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  String get prescriptionDate => isEnglish ? 'Dispensing date' : '조제일자';
  String get chooseDate => isEnglish ? 'Choose date' : '날짜 선택';
  String get invalidPrescriptionDate => isEnglish
      ? 'Enter a valid date as YYYY-MM-DD.'
      : '올바른 날짜를 YYYY-MM-DD 형식으로 입력해주세요.';
  String get scheduleSlots => isEnglish ? 'Medication times' : '실제 복약 시간대';
  String get scheduleSlotRequired => isEnglish
      ? 'Select at least one medication time.'
      : '복약 시간대를 하나 이상 선택해주세요.';
  String get invalidTotalDays => isEnglish
      ? 'Enter a number between 1 and 3650.'
      : '1일 이상 3650일 이하의 숫자를 입력해주세요.';

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

  String moreCount(int count) {
    return isEnglish ? '+$count more' : '+$count개 더 있음';
  }
}
