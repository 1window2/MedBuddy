// 파일명: manual_medication_entry_ui_boundary.dart
// 역할: 사진 선택을 포함한 복약정보 직접 등록과 일정 입력 화면을 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/check_saved_medication_control.dart';
import '../entities/manual_medication_entry_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: manual_medication_entry_ui_boundary.dart
// 역할: 사진이나 처방전이 없는 약을 사용자가 직접 등록하는 화면을 제공한다.

// 클래스명: ManualMedicationEntryUI
// 역할: 약 이름, 선택 사진, 복용 기간, 복용량, 시간대를 입력받아 저장 요청을 전달한다.
// 주요 책임:
// - 필수 입력과 날짜 범위를 화면에서 검증한다.
// - 카메라 또는 갤러리에서 선택한 알약 사진을 미리 보여준다.
// - 검증된 입력을 ManualMedicationEntry로 묶어 기존 저장 흐름에 전달한다.
class ManualMedicationEntryUI extends StatefulWidget {
  final UserSetting userSetting;
  final Future<MedicationSaveResult> Function(ManualMedicationEntry entry)
  onSaveRequested;
  final ImagePicker? imagePicker;

  const ManualMedicationEntryUI({
    super.key,
    required this.userSetting,
    required this.onSaveRequested,
    this.imagePicker,
  });

  @override
  State<ManualMedicationEntryUI> createState() =>
      _ManualMedicationEntryUIState();
}

class _ManualMedicationEntryUIState extends State<ManualMedicationEntryUI> {
  static const List<String> _dosageUnits = ['정', '캡슐', '포', 'mL', '방울'];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _medicationNameController =
      TextEditingController();
  final TextEditingController _dosageController = TextEditingController(
    text: '1',
  );
  late final ImagePicker _imagePicker;
  DateTime _startDate = _dateOnly(DateTime.now());
  DateTime _endDate = _dateOnly(DateTime.now());
  final Set<String> _selectedSlotKeys = {defaultMedicationScheduleSlotKey};
  String _dosageUnit = _dosageUnits.first;
  String _selectedImagePath = '';
  String _errorMessage = '';
  bool _isSaving = false;

  bool get _isEnglish =>
      widget.userSetting.language.trim().toLowerCase().startsWith('en');

  _ManualMedicationText get _text => _ManualMedicationText(_isEnglish);

  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? ImagePicker();
  }

  @override
  void dispose() {
    _medicationNameController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.pageBackground,
        foregroundColor: MedBuddyColors.textStrong,
        elevation: 0,
        title: Text(
          _text.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIntroNotice(),
                      const SizedBox(height: 20),
                      _buildPhotoSection(),
                      const SizedBox(height: 24),
                      _buildMedicationNameField(),
                      const SizedBox(height: 18),
                      _buildDosageFields(),
                      const SizedBox(height: 24),
                      _buildDateSection(),
                      const SizedBox(height: 24),
                      _buildScheduleSlotSection(),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _buildErrorNotice(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        border: Border.all(color: MedBuddyColors.successBorder),
        borderRadius: MedBuddyRadii.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: MedBuddyColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _text.intro,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: _text.photoTitle, optional: _text.optional),
        const SizedBox(height: 8),
        Text(
          _text.photoDescription,
          style: const TextStyle(color: MedBuddyColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: MedBuddyRadii.card,
          child: InkWell(
            key: const Key('manual-medication-photo'),
            borderRadius: MedBuddyRadii.card,
            onTap: _isSaving ? null : _selectImageSource,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 150),
              decoration: BoxDecoration(
                borderRadius: MedBuddyRadii.card,
                border: Border.all(color: MedBuddyColors.outline, width: 1.5),
              ),
              child: _selectedImagePath.isEmpty
                  ? _buildEmptyPhoto()
                  : _buildSelectedPhoto(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPhoto() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            color: MedBuddyColors.primary,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            _text.addPhoto,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPhoto() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: MedBuddyRadii.card,
          child: Image.file(
            File(_selectedImagePath),
            width: double.infinity,
            height: 210,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildEmptyPhoto(),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filled(
            key: const Key('manual-medication-remove-photo'),
            tooltip: _text.removePhoto,
            onPressed: () => setState(() => _selectedImagePath = ''),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.68),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: _text.nameTitle),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('manual-medication-name'),
          controller: _medicationNameController,
          enabled: !_isSaving,
          maxLength: 200,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: _text.nameHint,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return _text.nameRequired;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDosageFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: _text.dosageTitle),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('manual-medication-dosage'),
                controller: _dosageController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: _text.amount,
                  border: const OutlineInputBorder(),
                ),
                validator: _validateDosage,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const Key('manual-medication-unit'),
                initialValue: _dosageUnit,
                decoration: InputDecoration(
                  labelText: _text.unit,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final unit in _dosageUnits)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(_text.dosageUnitLabel(unit)),
                    ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _dosageUnit = value);
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: _text.periodTitle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DateButton(
                key: const Key('manual-medication-start-date'),
                label: _text.startDate,
                value: _formatDate(_startDate),
                onPressed: _isSaving ? null : () => _selectDate(true),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: _DateButton(
                key: const Key('manual-medication-end-date'),
                label: _text.endDate,
                value: _formatDate(_endDate),
                onPressed: _isSaving ? null : () => _selectDate(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _text.periodSummary(_endDate.difference(_startDate).inDays + 1),
          style: const TextStyle(
            color: MedBuddyColors.primaryDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSlotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: _text.slotTitle),
        const SizedBox(height: 8),
        Text(
          _text.slotDescription,
          style: const TextStyle(color: MedBuddyColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final slotKey in medicationScheduleSlotKeys)
              FilterChip(
                key: Key('manual-medication-slot-$slotKey'),
                label: Text(_text.slotLabel(slotKey)),
                selected: _selectedSlotKeys.contains(slotKey),
                onSelected: _isSaving
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected) {
                            _selectedSlotKeys.add(slotKey);
                          } else {
                            _selectedSlotKeys.remove(slotKey);
                          }
                          _errorMessage = '';
                        });
                      },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorNotice() {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: MedBuddyRadii.card,
          border: Border.all(color: const Color(0xFFFDA4AF)),
        ),
        child: Text(
          _errorMessage,
          style: const TextStyle(
            color: Color(0xFFBE123C),
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: FilledButton.icon(
        key: const Key('manual-medication-save'),
        onPressed: _isSaving ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: MedBuddyColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(
          _isSaving ? _text.saving : _text.save,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String? _validateDosage(String? value) {
    final dosage = double.tryParse((value ?? '').trim());
    if (dosage == null || dosage <= 0 || dosage > 10000) {
      return _text.invalidDosage;
    }
    return null;
  }

  Future<void> _selectImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(_text.camera),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(_text.gallery),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || source == null) {
      return;
    }
    final selectedImage = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
      maxHeight: 1800,
    );
    if (!mounted || selectedImage == null) {
      return;
    }
    setState(() {
      _selectedImagePath = selectedImage.path;
      _errorMessage = '';
    });
  }

  Future<void> _selectDate(bool selectsStartDate) async {
    final currentDate = selectsStartDate ? _startDate : _endDate;
    final firstDate = selectsStartDate ? DateTime(2000) : _startDate;
    final lastDate = selectsStartDate
        ? _dateOnly(DateTime.now().add(const Duration(days: 365)))
        : _startDate.add(const Duration(days: 3649));
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDate.isBefore(firstDate) ? firstDate : currentDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!mounted || selectedDate == null) {
      return;
    }
    setState(() {
      if (selectsStartDate) {
        _startDate = _dateOnly(selectedDate);
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = _dateOnly(selectedDate);
      }
      _errorMessage = '';
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (_selectedSlotKeys.isEmpty) {
      setState(() => _errorMessage = _text.slotRequired);
      return;
    }
    if (!isFormValid) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });
    final result = await widget.onSaveRequested(
      ManualMedicationEntry(
        medicationName: _medicationNameController.text.trim(),
        dosageAmount: _dosageController.text.trim(),
        dosageUnit: _dosageUnit,
        startDate: _startDate,
        endDate: _endDate,
        scheduleSlotKeys: _selectedSlotKeys.toList(growable: false),
        localImagePath: _selectedImagePath,
      ),
    );
    if (!mounted) {
      return;
    }
    if (!result.isCompleted) {
      setState(() {
        _isSaving = false;
        _errorMessage = result.message;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == MedicationSaveStatus.duplicate
              ? _text.duplicate
              : _text.saved,
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}.'
        '${value.month.toString().padLeft(2, '0')}.'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? optional;

  const _SectionTitle({required this.title, this.optional});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (optional != null) ...[
          const SizedBox(width: 8),
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
}

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onPressed;

  const _DateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: MedBuddyColors.textStrong,
        side: const BorderSide(color: MedBuddyColors.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ManualMedicationText {
  final bool isEnglish;

  const _ManualMedicationText(this.isEnglish);

  String get title => isEnglish ? 'Add Medication' : '약 직접 등록';
  String get intro => isEnglish
      ? 'Use the medication label or instructions. Do not guess uncertain information.'
      : '약 봉투나 복약 안내에 적힌 내용을 기준으로 입력해주세요. 확실하지 않은 내용은 임의로 입력하지 마세요.';
  String get photoTitle => isEnglish ? 'Pill photo' : '알약 사진';
  String get optional => isEnglish ? 'Optional' : '선택';
  String get photoDescription => isEnglish
      ? 'The photo stays only on this device.'
      : '선택한 사진은 이 기기의 앱 내부에만 저장됩니다.';
  String get addPhoto => isEnglish ? 'Add a pill photo' : '알약 사진 추가';
  String get removePhoto => isEnglish ? 'Remove photo' : '사진 삭제';
  String get nameTitle => isEnglish ? 'Medication name' : '약 이름';
  String get nameHint =>
      isEnglish ? 'Enter the label name' : '약 봉투에 적힌 이름을 입력하세요';
  String get nameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  String get dosageTitle => isEnglish ? 'Dose per intake' : '1회 복용량';
  String get amount => isEnglish ? 'Amount' : '수량';
  String get unit => isEnglish ? 'Unit' : '단위';
  String get invalidDosage =>
      isEnglish ? 'Enter a valid dose.' : '0보다 큰 올바른 복용량을 입력해주세요.';
  String dosageUnitLabel(String unit) {
    if (!isEnglish) {
      return unit;
    }
    return switch (unit) {
      '정' => 'Tablet',
      '캡슐' => 'Capsule',
      '포' => 'Packet',
      '방울' => 'Drop',
      _ => unit,
    };
  }

  String get periodTitle => isEnglish ? 'Medication period' : '복용 기간';
  String get startDate => isEnglish ? 'Start' : '시작일';
  String get endDate => isEnglish ? 'End' : '종료일';
  String periodSummary(int days) => isEnglish ? '$days day(s)' : '총 $days일 복용';
  String get slotTitle => isEnglish ? 'When to take' : '복용 시간대';
  String get slotDescription => isEnglish
      ? 'Choose every time slot shown on the medication instructions.'
      : '복약 안내에 적힌 시간대를 모두 선택해주세요.';
  String get slotRequired =>
      isEnglish ? 'Choose at least one time slot.' : '복용 시간대를 한 개 이상 선택해주세요.';
  String slotLabel(String key) {
    return switch (key) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => key,
    };
  }

  String get camera => isEnglish ? 'Take photo' : '카메라로 촬영';
  String get gallery => isEnglish ? 'Choose from gallery' : '갤러리에서 선택';
  String get save => isEnglish ? 'Save medication' : '복약 정보 저장';
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  String get saved => isEnglish ? 'Medication saved.' : '복약 정보를 저장했습니다.';
  String get duplicate =>
      isEnglish ? 'This medication is already saved.' : '이미 추가된 약입니다.';
}
