import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_schedule_review_ui_boundary.dart
// 역할: 처방전 OCR과 낱알약 식별 결과의 복약 일정을 저장 또는 분석 전에 확인하게 한다.

// 열거형명: MedicationScheduleReviewPurpose
// 역할: 검토 화면을 연 입력 경로에 따라 안내 문구와 완료 버튼의 의미를 구분한다.
enum MedicationScheduleReviewPurpose { prescriptionAnalysis, pillSave }

// 함수명: showMedicationScheduleReview
// 역할:
// - 인식된 하나 이상의 복약 일정을 한 화면에서 검토하게 한다.
// - 사용자가 취소하면 null, 확인하면 정규화된 일정 목록을 반환한다.
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

// 함수명: showMedicationScheduleEditor
// 역할: 복약 일정 한 건의 시작일, 복용량, 횟수, 기간과 시간대를 수정하게 한다.
Future<MedicationSchedule?> showMedicationScheduleEditor({
  required BuildContext context,
  required MedicationSchedule medicationSchedule,
  required UserSetting userSetting,
}) {
  return showDialog<MedicationSchedule>(
    context: context,
    builder: (dialogContext) => _MedicationScheduleEditorDialog(
      medicationSchedule: medicationSchedule,
      userSetting: userSetting,
    ),
  );
}

// 클래스명: _MedicationScheduleReviewSheet
// 역할: 여러 약의 핵심 복약 정보를 한 번에 비교하고 필요한 항목만 수정하게 한다.
class _MedicationScheduleReviewSheet extends StatefulWidget {
  final List<MedicationSchedule> initialSchedules;
  final UserSetting userSetting;
  final MedicationScheduleReviewPurpose purpose;

  const _MedicationScheduleReviewSheet({
    required this.initialSchedules,
    required this.userSetting,
    required this.purpose,
  });

  @override
  State<_MedicationScheduleReviewSheet> createState() =>
      _MedicationScheduleReviewSheetState();
}

class _MedicationScheduleReviewSheetState
    extends State<_MedicationScheduleReviewSheet> {
  late List<MedicationSchedule> _schedules;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    _schedules = List<MedicationSchedule>.of(widget.initialSchedules);
  }

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

  Future<void> _editSchedule(int index) async {
    final updatedSchedule = await showMedicationScheduleEditor(
      context: context,
      medicationSchedule: _schedules[index],
      userSetting: widget.userSetting,
    );
    if (!mounted || updatedSchedule == null) {
      return;
    }
    setState(() {
      _schedules[index] = updatedSchedule;
      _validationMessage = '';
    });
  }

  // 함수명: _confirmReview
  // 역할: 누락되거나 서로 맞지 않는 일정이 있으면 해당 약의 수정 창을 열고 유효한 목록만 반환한다.
  Future<void> _confirmReview() async {
    final invalidIndex = _schedules.indexWhere(
      (schedule) => !_isScheduleComplete(schedule),
    );
    if (invalidIndex >= 0) {
      final text = _MedicationScheduleReviewText(widget.userSetting.language);
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

class _MedicationScheduleReviewCard extends StatelessWidget {
  final int index;
  final MedicationSchedule medicationSchedule;
  final UserSetting userSetting;
  final VoidCallback onEditRequested;

  const _MedicationScheduleReviewCard({
    required this.index,
    required this.medicationSchedule,
    required this.userSetting,
    required this.onEditRequested,
  });

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

class _ScheduleSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String emptyValue;
  final double scale;

  const _ScheduleSummaryRow({
    required this.label,
    required this.value,
    required this.emptyValue,
    required this.scale,
  });

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

class _PillScheduleSafetyNotice extends StatelessWidget {
  final _MedicationScheduleReviewText text;
  final double scale;

  const _PillScheduleSafetyNotice({required this.text, required this.scale});

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

class _ScheduleValidationNotice extends StatelessWidget {
  final String message;
  final double scale;

  const _ScheduleValidationNotice({required this.message, required this.scale});

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
// 역할: 복약 일정 한 건의 입력값과 유효성 검사를 관리한다.
class _MedicationScheduleEditorDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final UserSetting userSetting;

  const _MedicationScheduleEditorDialog({
    required this.medicationSchedule,
    required this.userSetting,
  });

  @override
  State<_MedicationScheduleEditorDialog> createState() =>
      _MedicationScheduleEditorDialogState();
}

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

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _daysController.dispose();
    super.dispose();
  }

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

  void _setFrequency(int count) {
    setState(() {
      _frequencyCount = count;
      _selectedSlotKeys = medicationScheduleSlotKeysForFrequency(count).toSet();
      _showSlotValidationError = false;
    });
  }

  void _toggleSlot(String slotKey, bool selected) {
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
    setState(() => _startDate = selectedDate);
  }

  String? _validateDuration(String? value) {
    final days = int.tryParse(value?.trim() ?? '');
    if (days == null || days <= 0 || days > 3650) {
      return _MedicationScheduleReviewText(
        widget.userSetting.language,
      ).invalidDuration;
    }
    return null;
  }

  void _submit() {
    final hasValidSlots =
        _selectedSlotKeys.isNotEmpty &&
        _selectedSlotKeys.length == _frequencyCount;
    if (!hasValidSlots) {
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

String _formatDate(DateTime? date) {
  if (date == null) {
    return '';
  }
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _MedicationScheduleReviewText {
  final String language;

  const _MedicationScheduleReviewText(this.language);

  bool get isEnglish => language == 'en';
  String get reviewTitle => isEnglish ? 'Review medication plan' : '복약 정보 확인';
  String get prescriptionReviewDescription => isEnglish
      ? 'Review the OCR values before medication analysis. Edit only the incorrect entries.'
      : '약품 분석 전에 OCR로 인식한 값을 확인해주세요. 잘못된 항목만 수정하면 됩니다.';
  String get pillReviewDescription => isEnglish
      ? 'Set a medication plan for the selected pill candidate.'
      : '선택한 알약 후보의 복용 일정을 설정해주세요.';
  String get pillSafetyNotice => isEnglish
      ? 'A pill photo cannot determine your prescribed dose or duration. The values below are placeholders. Check the prescription or package before saving.'
      : '알약 사진만으로 실제 복용량과 기간을 알 수 없습니다. 아래 값은 임시 기본값이므로 처방전이나 약 봉투를 확인한 뒤 저장해주세요.';
  String get editTitle => isEnglish ? 'Edit medication plan' : '복약 정보 수정';
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  String get startDate => isEnglish ? 'Start date' : '복용 시작일';
  String get dosage => isEnglish ? 'Dose per intake' : '1회 복용량';
  String get dosageHint => isEnglish ? 'e.g. 1 tablet' : '예: 1정, 0.5정, 1포';
  String get dosageRequired =>
      isEnglish ? 'Enter the dose per intake.' : '1회 복용량을 입력해주세요.';
  String get dailyFrequency => isEnglish ? 'Times per day' : '1일 복용 횟수';
  String get duration => isEnglish ? 'Duration (days)' : '복용 기간(일)';
  String get scheduleSlots => isEnglish ? 'Medication times' : '복용 시간대';
  String get invalidDuration => isEnglish
      ? 'Enter a duration between 1 and 3650 days.'
      : '복용 기간은 1일부터 3650일 사이로 입력해주세요.';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get apply => isEnglish ? 'Apply' : '적용';
  String get edit => isEnglish ? 'Edit medication plan' : '복약 정보 수정';
  String get reviewNeeded => isEnglish ? 'Review needed' : '확인 필요';
  String get confirmAndAnalyze =>
      isEnglish ? 'Confirm and analyze' : '확인 후 분석하기';
  String get confirmAndSave => isEnglish ? 'Confirm and save' : '확인하고 저장하기';

  String frequencyValue(int count) => isEnglish ? '$count times' : '$count회';
  String durationValue(int days) => isEnglish ? '$days days' : '$days일';
  String incompleteSchedule(String medicationName) => isEnglish
      ? 'Review all required values for $medicationName.'
      : '$medicationName의 시작일, 복용량, 횟수, 기간과 시간대를 모두 확인해주세요.';
  String scheduleSlotCountMismatch(int frequency) => isEnglish
      ? 'Select $frequency medication time(s).'
      : '1일 $frequency회에 맞게 복용 시간대를 $frequency개 선택해주세요.';

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
