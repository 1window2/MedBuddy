import 'package:flutter/material.dart';

import '../controls/check_saved_medication_control.dart';
import '../entities/json_value_reader.dart';
import '../entities/manual_medication_entry_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_dose_rhythm.dart';
import '../entities/medication_history_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_schedule_limits.dart';
import '../entities/medication_slot_label.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_confirm_dialog.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medication_dosing_mode_selector.dart';
import '../widgets/medication_entry_fields.dart';

// 기존 기록을 지우지 않는 처방 변경을 입력하고 적용일과 변경 내용을 최종 확인한다.
class MedicationRegimenEditorUI extends StatefulWidget {
  final MedicationDetail medication;
  final MedicationRegimenAction action;
  final bool isEnglish;
  final DateTime Function()? clock;
  final Future<MedicationRegimenResult> Function(MedicationRegimenChange)
  onSubmit;

  const MedicationRegimenEditorUI({
    super.key,
    required this.medication,
    required this.action,
    required this.onSubmit,
    this.isEnglish = false,
    this.clock,
  });

  @override
  State<MedicationRegimenEditorUI> createState() =>
      _MedicationRegimenEditorUIState();
}

class _MedicationRegimenEditorUIState extends State<MedicationRegimenEditorUI> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late DateTime _endDate;
  late final DateTime _originalCourseStart;
  String? _dosageUnit;
  late String _initialDoseAmount;
  String? _initialDoseUnit;
  late DateTime _effectiveDate;
  late bool _asNeeded;
  late String _doseDays;
  late Set<String> _slots;
  bool _busy = false;
  bool _mustReload = false;
  MedicationRegimenChange? _pendingChange;
  String? _error;

  bool get _english => widget.isEnglish;
  bool get _stopping => widget.action == MedicationRegimenAction.stop;
  bool get _locked => _busy || _pendingChange != null || _mustReload;
  String get _title => switch (widget.action) {
    MedicationRegimenAction.edit => _text('약 정보 수정', 'Edit medication'),
    MedicationRegimenAction.stop => _text('복용 중단', 'Stop medication'),
    MedicationRegimenAction.replace => _text('처방 교체', 'Replace medication'),
  };
  String get _dateLabel => switch (widget.action) {
    MedicationRegimenAction.edit => _text('변경 시작일', 'Change start date'),
    MedicationRegimenAction.stop => _text('복용 중단일', 'Stop date'),
    MedicationRegimenAction.replace => _text('복용 시작일', 'Medication start date'),
  };
  String _text(String ko, String en) => _english ? en : ko;

  // 기기 시간대와 무관하게 복용 이력·서버와 같은 한국 날짜를 사용한다.
  DateTime get _today {
    final day = MedicationHistoryDates.today((widget.clock ?? DateTime.now)());
    return DateTime(day.year, day.month, day.day);
  }

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    final replacing = widget.action == MedicationRegimenAction.replace;
    _name = TextEditingController(text: medication.itemName);
    // 온전히 분리되는 표준 단위만 수량·단위 입력으로 옮기고 나머지는 원문을 유지한다.
    final parsedDose = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)\s*(정|캡슐|포|mL|방울)$',
    ).firstMatch(medication.dosagePerTime.trim());
    _dosageUnit = replacing
        ? medicationEntryDoseUnits.first
        : parsedDose?.group(2);
    _dosage = TextEditingController(
      text: replacing ? '' : parsedDose?.group(1) ?? medication.dosagePerTime,
    );
    _initialDoseAmount = _dosage.text;
    _initialDoseUnit = _dosageUnit;
    final today = _today;
    _effectiveDate = today;
    final earliest =
        medication.regimenEffectiveFrom ??
        medication.prescriptionDate ??
        medication.createdDate;
    if (earliest != null &&
        earliest.isAfter(_effectiveDate) &&
        !earliest.isAfter(latestMedicationStartDate(today))) {
      _effectiveDate = DateTime(earliest.year, earliest.month, earliest.day);
    }
    // 변경 시작일을 옮겨도 원래 복용 기간의 기준 날짜는 달라지지 않는다.
    final originalStart =
        medication.prescriptionDate ?? medication.createdDate ?? _effectiveDate;
    _originalCourseStart = DateTime(
      originalStart.year,
      originalStart.month,
      originalStart.day,
    );
    _endDate = replacing
        ? _effectiveDate
        : DateTime(
            _courseStart.year,
            _courseStart.month,
            _courseStart.day +
                medicationDayCountFromText(medication.totalDays) -
                1,
          );
    _asNeeded = replacing ? false : medication.isAsNeeded;
    _doseDays = replacing || medication.isAsNeeded
        ? ''
        : requiresDoseScheduleReview(medication.dailyFrequency)
        ? medication.dailyFrequency
        : readDoseCycle(medication.dailyFrequency).isDaily
        ? ''
        : medication.dailyFrequency.split(',').first.trim();
    _slots = replacing
        ? <String>{}
        : medication.scheduleSlotKeys.isNotEmpty
        ? medication.scheduleSlotKeys.toSet()
        : medicationScheduleSlotKeysForFrequency(
            medicationScheduleCountFromText(medication.dailyFrequency),
          ).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              MedBuddyPageHeader(
                title: _title,
                subtitle: switch (widget.action) {
                  MedicationRegimenAction.edit => _text(
                    '약 정보와 복용 일정을 변경합니다.',
                    'Update medication details and the dosing schedule.',
                  ),
                  MedicationRegimenAction.stop => _text(
                    '중단할 약과 복용 중단일을 확인합니다.',
                    'Review the medication and when to stop it.',
                  ),
                  MedicationRegimenAction.replace => _text(
                    '새 약으로 교체하고 이전 기록을 보관합니다.',
                    'Replace a medication and keep earlier records.',
                  ),
                },
                leading: IconButton(
                  tooltip: _text('뒤로', 'Back'),
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: MedBuddySpacing.contentMaxWidth,
                    ),
                    child: Form(
                      key: _form,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          // 화면 밖의 필수 입력칸도 함께 검증하도록 폼 전체를 유지한다.
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_stopping) ...[
                                MedicationEntrySectionTitle(
                                  title: _text('약 이름', 'Medication name'),
                                ),
                                const SizedBox(height: 8),
                                Text(widget.medication.displayName),
                                const SizedBox(height: 24),
                                Text(
                                  _dateLabel,
                                  style: MedBuddyTextStyles.formSectionTitle,
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  label: _dateLabel,
                                  child: OutlinedButton(
                                    key: const Key('regimen-effective-date'),
                                    onPressed: _locked
                                        ? null
                                        : _pickEffectiveDate,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.event_outlined),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            formatJsonDate(_effectiveDate)!,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.edit_calendar_outlined,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _text(
                                    '이날부터 복용 일정과 알림에서 제외됩니다. 약 정보와 기존 기록은 남습니다. (한국 시간)',
                                    'Scheduled doses and reminders stop on this date. Medication information and earlier records are kept. (Korea time)',
                                  ),
                                  style: const TextStyle(
                                    color: MedBuddyColors.textMuted,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ] else ...[
                                MedicationEntryNameField(
                                  fieldKey: const Key('regimen-name'),
                                  controller: _name,
                                  enabled: !_locked,
                                  title: _text('약 이름', 'Medication name'),
                                  hint: _text(
                                    '약 봉투에 적힌 이름을 입력하세요',
                                    'Enter the label name',
                                  ),
                                  validator: _required,
                                ),
                                const SizedBox(height: 24),
                                MedicationEntryDoseFields(
                                  keyPrefix: 'regimen',
                                  controller: _dosage,
                                  enabled: !_locked,
                                  title: _text('1회 복용량', 'Dose per intake'),
                                  amountLabel: _text('수량', 'Amount'),
                                  unitLabel: _text('단위', 'Unit'),
                                  unit: _dosageUnit,
                                  unitText: _unitLabel,
                                  onUnitChanged: (value) =>
                                      setState(() => _dosageUnit = value),
                                  validator: _validateDose,
                                ),
                                const SizedBox(height: 24),
                                if (widget.action ==
                                    MedicationRegimenAction.edit) ...[
                                  MedicationEntrySectionTitle(
                                    title: _dateLabel,
                                  ),
                                  const SizedBox(height: 10),
                                  MedicationEntryDateButton(
                                    buttonKey: const Key(
                                      'regimen-effective-date',
                                    ),
                                    label: _text(
                                      '변경한 용량·일정 반영 (한국 시간)',
                                      'Updated dose and schedule (Korea time)',
                                    ),
                                    value: formatJsonDate(_effectiveDate)!,
                                    onPressed: _locked
                                        ? null
                                        : _pickEffectiveDate,
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                _buildPeriodFields(),
                                const SizedBox(height: 24),
                                MedicationDosingModeSelector(
                                  keyPrefix: 'regimen',
                                  isAsNeeded: _asNeeded,
                                  isEnglish: _english,
                                  onChanged: _locked
                                      ? null
                                      : (value) =>
                                            setState(() => _asNeeded = value),
                                ),
                                if (!_asNeeded) ...[
                                  const SizedBox(height: 24),
                                  MedicationEntrySectionTitle(
                                    title: _text('복용 주기', 'Dose days'),
                                  ),
                                  const SizedBox(height: 8),
                                  MedicationEntryCycleChoices(
                                    keyPrefix: 'regimen-cycle',
                                    value: _doseDays,
                                    label: _doseDaysLabel,
                                    onChanged: _locked
                                        ? null
                                        : (value) =>
                                              setState(() => _doseDays = value),
                                  ),
                                  if (_doseDays.isNotEmpty &&
                                      !requiresDoseScheduleReview(
                                        _doseDays,
                                      )) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      describeDoseCycle(
                                        readDoseCycle(_doseDays),
                                        isEnglish: _english,
                                        startDate: _courseStart,
                                        courseDays: _courseDays,
                                      ),
                                      style: const TextStyle(
                                        color: MedBuddyColors.textMuted,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  MedicationEntrySectionTitle(
                                    title: _text('복용 시간대', 'Dose times'),
                                  ),
                                  const SizedBox(height: 8),
                                  MedicationEntrySlotChoices(
                                    keyPrefix: 'regimen-slot',
                                    values: _slots,
                                    label: (slot) => medicationSlotLabel(
                                      slot,
                                      isEnglish: _english,
                                    ),
                                    onChanged: _locked
                                        ? null
                                        : (slot, selected) => setState(() {
                                            selected
                                                ? _slots.add(slot)
                                                : _slots.remove(slot);
                                          }),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                  ),
                  child: SingleChildScrollView(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const Key('regimen-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                key: const Key('regimen-submit'),
                onPressed: _busy || _mustReload ? null : _submit,
                icon: _busy && _pendingChange != null
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _busy
                      ? _pendingChange == null
                            ? _text('변경 확인 중', 'Confirming')
                            : _text('저장 중', 'Saving')
                      : _pendingChange != null
                      ? _text('같은 내용으로 다시 시도', 'Retry this change')
                      : _text('변경 내용 확인', 'Review changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime get _courseStart {
    final start = widget.action == MedicationRegimenAction.replace
        ? _effectiveDate
        : _originalCourseStart;
    return DateTime(start.year, start.month, start.day);
  }

  int get _courseDays => inclusiveMedicationCourseDays(_courseStart, _endDate);

  String get _doseText {
    // 다른 항목만 수정할 때 원래 복용량의 공백·표현을 불필요하게 바꾸지 않는다.
    if (widget.action == MedicationRegimenAction.edit &&
        _dosage.text == _initialDoseAmount &&
        _dosageUnit == _initialDoseUnit) {
      return widget.medication.dosagePerTime;
    }
    return '${_dosage.text.trim()}${_dosageUnit ?? ''}';
  }

  String _unitLabel(String value) => !_english
      ? value
      : switch (value) {
          '정' => 'Tablet',
          '캡슐' => 'Capsule',
          '포' => 'Packet',
          '방울' => 'Drop',
          _ => value,
        };

  String? _validateDose(String? value) {
    final required = _required(value);
    if (required != null) return required;
    if (_dosageUnit == null) return null;
    final amount = double.tryParse(value!.trim());
    return amount == null || !amount.isFinite || amount <= 0 || amount > 10000
        ? _text('0보다 큰 올바른 복용량을 입력해주세요.', 'Enter a valid dose.')
        : null;
  }

  Widget _buildPeriodFields() {
    final replacing = widget.action == MedicationRegimenAction.replace;
    return MedicationEntryPeriodFields(
      title: _text('복용 기간', 'Medication period'),
      startButton: MedicationEntryDateButton(
        buttonKey: Key(
          replacing ? 'regimen-effective-date' : 'regimen-course-start',
        ),
        label: replacing
            ? _dateLabel
            : _text('기존 복용 시작일', 'Original start date'),
        value: formatJsonDate(_courseStart)!,
        onPressed: replacing && !_locked ? _pickEffectiveDate : null,
      ),
      endButton: MedicationEntryDateButton(
        buttonKey: const Key('regimen-end-date'),
        label: _text('복용 종료일', 'End date'),
        value: formatJsonDate(_endDate)!,
        onPressed: _locked ? null : _pickEndDate,
      ),
      summary: _text('총 $_courseDays일 복용', '$_courseDays day(s)'),
    );
  }

  Future<void> _pickEndDate() async {
    if (_locked) return;
    final first = _effectiveDate.isAfter(_courseStart)
        ? _effectiveDate
        : _courseStart;
    final last = latestMedicationEndDate(_courseStart);
    if (first.isAfter(last)) {
      setState(
        () => _error = _text(
          '기존 복용 시작일부터 3650일을 넘길 수 없습니다. 새 처방이면 처방 교체를 이용해 주세요.',
          'The original course cannot exceed 3650 days. Use replacement for a new prescription.',
        ),
      );
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(first)
          ? first
          : _endDate.isAfter(last)
          ? last
          : _endDate,
      firstDate: first,
      lastDate: last,
      currentDate: _today,
    );
    if (selected != null && mounted && !_locked) {
      setState(() {
        _endDate = selected;
        _error = null;
      });
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? _text('필수 항목입니다.', 'Required.')
      : null;

  // 확인창의 복용 주기 문구. 저장 문구("주 1회, 1일 2회")는 한국어라 영어 화면에서는 같은 뜻으로 바꿔 보여준다.
  String get _frequencySummary {
    final count = _slots.length;
    if (!_english) return composeDoseFrequency(_doseDays, count);
    final perDay = count == 1 ? 'once a day' : '$count times a day';
    if (_doseDays.isEmpty) return 'Daily, $perDay';
    return count <= 1 ? _doseDaysLabel(_doseDays) : '${_doseDaysLabel(_doseDays)}, $perDay';
  }

  String _doseDaysLabel(String value) => switch (value) {
    '' => _text('매일', 'Daily'),
    '격일' => _text('격일', 'Every other day'),
    '주 1회' => _text('주 1회', 'Weekly'),
    '월 1회' => _text('월 1회', 'Once a month'),
    _ => value,
  };

  Future<void> _pickEffectiveDate() async {
    if (_locked) return;
    final today = _today;
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveDate.isBefore(today) ? today : _effectiveDate,
      firstDate: today,
      lastDate: latestMedicationStartDate(today),
      currentDate: today,
    );
    if (selected != null && mounted && !_locked) {
      setState(() {
        _effectiveDate = selected;
        if (widget.action == MedicationRegimenAction.replace) {
          if (_endDate.isBefore(selected)) _endDate = selected;
          final last = latestMedicationEndDate(selected);
          if (_endDate.isAfter(last)) _endDate = last;
        }
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy || _mustReload) return;
    FocusScope.of(context).unfocus();
    if (_pendingChange == null) {
      if (!(_form.currentState?.validate() ?? false)) return;
      if (_effectiveDate.isBefore(_today)) {
        setState(
          () => _error = _text(
            '한국 날짜가 바뀌었습니다. $_dateLabel을 다시 선택해 주세요.',
            'The date in Korea has changed. Select the $_dateLabel again.',
          ),
        );
        return;
      }
      if (!_stopping &&
          !_asNeeded &&
          (_slots.isEmpty || requiresDoseScheduleReview(_doseDays))) {
        setState(
          () => _error = _text(
            '처방에 맞는 복용 주기와 시간대를 확인해 주세요.',
            'Confirm a supported dose cycle and at least one time slot.',
          ),
        );
        return;
      }
      if (!_stopping) {
        if (!isValidMedicationCourseDays(_courseDays)) {
          setState(
            () => _error = _text(
              '복용 기간은 1~3650일로 선택해 주세요.',
              'Choose a course of 1 to 3650 days.',
            ),
          );
          return;
        }
        if (_endDate.isBefore(_effectiveDate)) {
          setState(
            () => _error = _text(
              '$_dateLabel이 복용 종료일보다 늦습니다. 기간을 확인해 주세요.',
              'The course ends before the $_dateLabel. Check its duration.',
            ),
          );
          return;
        }
        if (_effectiveDate.isBefore(_courseStart)) {
          setState(
            () => _error = _text(
              '변경 시작일은 기존 복용 시작일보다 빠를 수 없습니다.',
              'The change cannot begin before the original course.',
            ),
          );
          return;
        }
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      final doseLabel = localizedDoseAmountLabel(
        _doseText,
        _english ? 'en' : 'ko',
      );
      final confirmed = await showMedBuddyConfirmDialog(
        context,
        title: _title,
        message:
            '${widget.medication.displayName}\n$_dateLabel: ${formatJsonDate(_effectiveDate)}\n\n${_stopping ? _text('이 날부터 복용 일정과 알림에서 제외합니다.', 'Remove this medication from scheduled doses and reminders from this date.') : '${_name.text.trim()} · $doseLabel\n${_asNeeded ? _text('필요시 복용', 'As needed') : _frequencySummary}\n${_text('복용 종료일', 'End date')}: ${formatJsonDate(_endDate)} · ${_text('총 $_courseDays일', '$_courseDays day(s)')}'}\n\n${_text('기존 복용 기록은 삭제하지 않습니다. 처방·복약지도에 따른 변경이 맞나요?', 'Earlier records will not be deleted. Does this match your prescription or professional instructions?')}',
        cancelLabel: _text('취소', 'Cancel'),
        confirmLabel: _text('확인 후 적용', 'Confirm change'),
        confirmKey: const Key('regimen-confirm'),
        barrierDismissible: false,
        scrollable: true,
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _busy = false);
        return;
      }
      _pendingChange = MedicationRegimenChange(
        action: widget.action,
        effectiveDate: _effectiveDate,
        expectedRevision: widget.medication.regimenRevision,
        changes: _stopping
            ? const {}
            : {
                'item_name': _name.text.trim(),
                'dosage_per_time': _doseText,
                'daily_frequency': _asNeeded
                    ? '필요시 복용'
                    : composeDoseFrequency(_doseDays, _slots.length),
                'total_days': '$_courseDays',
                if (widget.action == MedicationRegimenAction.replace)
                  'prescription_date': formatJsonDate(_courseStart),
                'schedule_slot_keys': _asNeeded
                    ? <String>[]
                    : medicationScheduleSlotKeys
                          .where(_slots.contains)
                          .toList(),
                'dosing_mode': _asNeeded ? 'as_needed' : 'scheduled',
              },
      );
    } else {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    setState(() {});
    MedicationRegimenResult result;
    try {
      result = await widget.onSubmit(_pendingChange!);
    } catch (_) {
      result = const MedicationRegimenResult(
        failure: MedicationRegimenFailure.network,
      );
    }
    if (!mounted) return;
    if (result.success) {
      setState(() => _busy = false);
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message(_english);
      _mustReload = {
        MedicationRegimenFailure.conflict,
        MedicationRegimenFailure.forbidden,
        MedicationRegimenFailure.missing,
        MedicationRegimenFailure.cancelled,
      }.contains(result.failure);
      if (result.failure != MedicationRegimenFailure.network) {
        _pendingChange = null;
      }
    });
  }
}

String regimenActionLabel(MedicationRegimenAction action, bool english) =>
    switch (action) {
      MedicationRegimenAction.edit => english ? 'Edit information' : '정보 수정',
      MedicationRegimenAction.stop =>
        english ? 'Stop as prescribed' : '처방에 따른 복용 중단',
      MedicationRegimenAction.replace =>
        english ? 'Replace with a new prescription' : '새 처방으로 교체',
    };
