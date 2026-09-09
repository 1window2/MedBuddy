// 파일명: manual_medication_entry_ui_boundary.dart
// 역할: 약품명·사진·기간·복약 시간대 직접 입력을 제공한다.

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
// 역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력을 담당한다.
// 주요 책임:
// - 필수 입력과 날짜 범위를 화면에서 검증한다.
// - 카메라 또는 갤러리에서 선택한 알약 사진을 미리 보여준다.
// - 검증된 입력을 ManualMedicationEntry로 묶어 기존 저장 흐름에 전달한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onSaveRequested (Future<MedicationSaveResult> Function(ManualMedicationEntry entry)): 검증한 약품과 복약 정보를 저장할 콜백.
// - imagePicker (ImagePicker?): 카메라·갤러리 이미지 선택 의존성.
class ManualMedicationEntryUI extends StatefulWidget {
  final UserSetting userSetting;
  final Future<MedicationSaveResult> Function(ManualMedicationEntry entry)
  onSaveRequested;
  final ImagePicker? imagePicker;

  // 함수이름: ManualMedicationEntryUI
  // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onSaveRequested (Future<MedicationSaveResult> Function(ManualMedicationEntry entry)): 검증한 약품과 복약 정보를 저장할 콜백.
  // - imagePicker (ImagePicker?): 카메라·갤러리 이미지 선택 의존성.
  // 반환값: 입력 설정이 반영된 ManualMedicationEntryUI 인스턴스.
  const ManualMedicationEntryUI({
    super.key,
    required this.userSetting,
    required this.onSaveRequested,
    this.imagePicker,
  });

  // 함수이름: createState
  // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _ManualMedicationEntryUIState 인스턴스.
  @override
  State<ManualMedicationEntryUI> createState() =>
      _ManualMedicationEntryUIState();
}

// 클래스명: _ManualMedicationEntryUIState
// 역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 화면 상태를 관리한다.
// 주요 책임:
// - 사용자가 입력한 정보로 일정을 저장한다는 안내를 표시한다.
// - 선택 사진 또는 빈 사진 영역과 사진 추가 동작을 배치한다.
// - 직접 입력 약품에 선택 사진을 추가할 수 있는 빈 영역을 표시한다.
// 속성:
// - _imagePicker (ImagePicker): 카메라·갤러리 이미지 선택 의존성.
// - _endDate (DateTime): 복용 기간의 마지막 날짜.
// - _isSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
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

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isEnglish =>
      widget.userSetting.language.trim().toLowerCase().startsWith('en');

  // 함수이름: _text
  // 함수역할: 현재 언어에 맞는 약품명·사진·기간·복약 시간대 직접 입력 문구 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: _ManualMedicationText: 현재 화면 언어의 문구 제공 객체.
  _ManualMedicationText get _text => _ManualMedicationText(_isEnglish);

  // 함수이름: initState
  // 함수역할: 주입된 이미지 선택기를 사용하거나 기본 선택기를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? ImagePicker();
  }

  // 함수이름: dispose
  // 함수역할: _medicationNameController, _dosageController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _medicationNameController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 사진을 포함한 약품명·처방일·복용 일정 직접 입력 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _buildIntroNotice
  // 함수역할: 사용자가 입력한 정보로 일정을 저장한다는 안내를 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _buildPhotoSection
  // 함수역할: 선택 사진 또는 빈 사진 영역과 사진 추가 동작을 배치한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _buildEmptyPhoto
  // 함수역할: 직접 입력 약품에 선택 사진을 추가할 수 있는 빈 영역을 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _buildSelectedPhoto
  // 함수역할: 선택한 로컬 사진과 제거 버튼을 표시하고 로드 실패는 빈 사진 영역으로 대체한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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
            // 함수이름: _buildSelectedPhoto.errorBuilder callback
            // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
            // 매개변수:
            // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
            // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
            // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
            errorBuilder: (_, _, _) => _buildEmptyPhoto(),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filled(
            key: const Key('manual-medication-remove-photo'),
            tooltip: _text.removePhoto,
            // 함수이름: _buildSelectedPhoto.setState callback
            // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_selectedImagePath = ''`로 갱신한다.
            // 매개변수:
            // - 없음.
            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
            // 함수이름: _buildSelectedPhoto.onPressed callback
            // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에서 캡처된 작업 `setState(() => _selectedImagePath = '')`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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

  // 함수이름: _buildMedicationNameField
  // 함수역할: 필수 약품명 입력과 빈 이름 검증을 연결한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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
          // 함수이름: _buildMedicationNameField.validator callback
          // 함수역할: 입력값을 `_text.nameRequired; null` 조건으로 검증한다.
          // 매개변수:
          // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
          // 반환값: 유효하지 않으면 검증 문구, 유효하면 null.
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

  // 함수이름: _buildDosageFields
  // 함수역할: 1회 복용량 숫자 입력과 단위 선택을 저장 상태에 맞게 제어한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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
                    // 함수이름: _buildDosageFields.onChanged callback
                    // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에서 캡처된 작업 `setState(() => _dosageUnit = value)`을 실행한다.
                    // 매개변수:
                    // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : (value) {
                        if (value != null) {
                          // 함수이름: _buildDosageFields.setState callback
                          // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_dosageUnit = value`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _buildDateSection
  // 함수역할: 복용 시작·종료 날짜와 계산된 복용 기간을 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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
                // 함수이름: _buildDateSection.onPressed callback
                // 함수역할: 허용 범위 안의 시작·종료 날짜를 선택하고 시작일 이후로 종료일을 보정한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
                // 함수이름: _buildDateSection.onPressed callback
                // 함수역할: 허용 범위 안의 시작·종료 날짜를 선택하고 시작일 이후로 종료일을 보정한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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

  // 함수이름: _buildScheduleSlotSection
  // 함수역할: 아침·점심·저녁·취침 전 복약 시간대를 복수 선택하게 한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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
                    // 함수이름: _buildScheduleSlotSection.onSelected callback
                    // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에서 캡처된 작업 `setState(() {if (selected) {_selectedSlotKeys.add(slotKey);} else {_selectedSlotKeys.remove(slotKey);} _errorMessage = '';})`을 실행한다.
                    // 매개변수:
                    // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    : (selected) {
                        // 함수이름: _buildScheduleSlotSection.setState callback
                        // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_errorMessage = ''`로 갱신한다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _buildErrorNotice
  // 함수역할: 직접 입력 오류를 스크린 리더가 알 수 있는 live region에 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _buildSaveBar
  // 함수역할: 저장 진행 중 중복 입력을 막는 고정 저장 버튼을 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 쓰는 위젯 트리.
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

  // 함수이름: _validateDosage
  // 함수역할: 1회 복용량이 0보다 크고 10000 이하인 숫자인지 검증한다.
  // 매개변수:
  // - value (String?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? _validateDosage(String? value) {
    final dosage = double.tryParse((value ?? '').trim());
    if (dosage == null || dosage <= 0 || dosage > 10000) {
      return _text.invalidDosage;
    }
    return null;
  }

  // 함수이름: _selectImageSource
  // 함수역할: 카메라·갤러리 선택 후 크기 제한으로 사진을 가져와 로컬 경로를 보관한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _selectImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      // 함수이름: _selectImageSource.builder callback
      // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력에 Icon을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(_text.camera),
                // 함수이름: _selectImageSource.onTap callback
                // 함수역할: `Navigator.pop(sheetContext, ImageSource.camera)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                // 매개변수:
                // - 없음.
                // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(_text.gallery),
                // 함수이름: _selectImageSource.onTap callback
                // 함수역할: `Navigator.pop(sheetContext, ImageSource.gallery)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                // 매개변수:
                // - 없음.
                // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
    // 함수이름: _selectImageSource.setState callback
    // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_selectedImagePath = selectedImage.path; _errorMessage = ''`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _selectedImagePath = selectedImage.path;
      _errorMessage = '';
    });
  }

  // 함수이름: _selectDate
  // 함수역할: 허용 범위 안의 시작·종료 날짜를 선택하고 시작일 이후로 종료일을 보정한다.
  // 매개변수:
  // - selectsStartDate (bool): 종료일 대신 시작일을 편집할지 여부.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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
    // 함수이름: _selectDate.setState callback
    // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_startDate = _dateOnly(selectedDate); _endDate = _startDate; _endDate = _dateOnly(selectedDate)`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _submit
  // 함수역할: 필수 값과 시간대를 검증해 직접 입력 약을 저장하고 중복·실패·완료 결과를 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (_selectedSlotKeys.isEmpty) {
      // 함수이름: _submit.setState callback
      // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_errorMessage = _text.slotRequired`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _errorMessage = _text.slotRequired);
      return;
    }
    if (!isFormValid) {
      return;
    }

    // 함수이름: _submit.setState callback
    // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_isSaving = true; _errorMessage = ''`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
      // 함수이름: _submit.setState callback
      // 함수역할: 사진을 포함한 약품명·처방일·복용 일정 직접 입력의 입력·요청 상태를 `_isSaving = false; _errorMessage = result.message`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _dateOnly
  // 함수역할: 시·분·초를 버리고 같은 연·월·일의 자정 날짜를 만든다.
  // 매개변수:
  // - value (DateTime): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: DateTime: 허용 범위 또는 시각 제거 규칙을 반영한 날짜.
  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  // 함수이름: _formatDate
  // 함수역할: 날짜를 4자리 연도와 두 자리 월·일의 점 구분 형식으로 표시한다.
  // 매개변수:
  // - value (DateTime): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  static String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}.'
        '${value.month.toString().padLeft(2, '0')}.'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

// 클래스명: _SectionTitle
// 역할: 직접 입력 폼의 항목 그룹 제목을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 직접 입력 폼의 항목 그룹 제목 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - optional (String?): 입력란·선택지·명령을 구분해 표시할 문구.
class _SectionTitle extends StatelessWidget {
  final String title;
  final String? optional;

  // 함수이름: _SectionTitle
  // 함수역할: 직접 입력 폼의 항목 그룹 제목에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - optional (String?): 입력란·선택지·명령을 구분해 표시할 문구.
  // 반환값: 입력 설정이 반영된 _SectionTitle 인스턴스.
  const _SectionTitle({required this.title, this.optional});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 직접 입력 폼의 항목 그룹 제목 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 직접 입력 폼의 항목 그룹 제목에 쓰는 위젯 트리.
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

// 클래스명: _DateButton
// 역할: 복용 날짜 선택과 현재 날짜 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복용 날짜 선택과 현재 날짜 표시 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onPressed;

  // 함수이름: _DateButton
  // 함수역할: 복용 날짜 선택과 현재 날짜 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _DateButton 인스턴스.
  const _DateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복용 날짜 선택과 현재 날짜 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복용 날짜 선택과 현재 날짜 표시에 쓰는 위젯 트리.
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

// 클래스명: _ManualMedicationText
// 역할: 약품명·사진·기간·복약 시간대 직접 입력에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 약품명·사진·기간·복약 시간대 직접 입력에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
class _ManualMedicationText {
  final bool isEnglish;

  // 함수이름: _ManualMedicationText
  // 함수역할: 약품명·사진·기간·복약 시간대 직접 입력에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // 반환값: 입력 설정이 반영된 _ManualMedicationText 인스턴스.
  const _ManualMedicationText(this.isEnglish);

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 직접 등록" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Add Medication' : '약 직접 등록';
  // 함수이름: intro
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 봉투나 복약 안내에 적힌 내용을 기준으로 입력해주세요. 확실하지 않은 내용은 임의로 입력하지 마세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get intro => isEnglish
      ? 'Use the medication label or instructions. Do not guess uncertain information.'
      : '약 봉투나 복약 안내에 적힌 내용을 기준으로 입력해주세요. 확실하지 않은 내용은 임의로 입력하지 마세요.';
  // 함수이름: photoTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 사진" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get photoTitle => isEnglish ? 'Pill photo' : '알약 사진';
  // 함수이름: optional
  // 함수역할: 현재 언어와 입력값에 맞춰 "Optional" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get optional => isEnglish ? 'Optional' : '선택';
  // 함수이름: photoDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택한 사진은 이 기기의 앱 내부에만 저장됩니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get photoDescription => isEnglish
      ? 'The photo stays only on this device.'
      : '선택한 사진은 이 기기의 앱 내부에만 저장됩니다.';
  // 함수이름: addPhoto
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약 사진 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addPhoto => isEnglish ? 'Add a pill photo' : '알약 사진 추가';
  // 함수이름: removePhoto
  // 함수역할: 현재 언어와 입력값에 맞춰 "사진 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get removePhoto => isEnglish ? 'Remove photo' : '사진 삭제';
  // 함수이름: nameTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nameTitle => isEnglish ? 'Medication name' : '약 이름';
  // 함수이름: nameHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 봉투에 적힌 이름을 입력하세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nameHint =>
      isEnglish ? 'Enter the label name' : '약 봉투에 적힌 이름을 입력하세요';
  // 함수이름: nameRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름을 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  // 함수이름: dosageTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 복용량" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosageTitle => isEnglish ? 'Dose per intake' : '1회 복용량';
  // 함수이름: amount
  // 함수역할: 현재 언어와 입력값에 맞춰 "Amount" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get amount => isEnglish ? 'Amount' : '수량';
  // 함수이름: unit
  // 함수역할: 현재 언어와 입력값에 맞춰 "Unit" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get unit => isEnglish ? 'Unit' : '단위';
  // 함수이름: invalidDosage
  // 함수역할: 현재 언어와 입력값에 맞춰 "0보다 큰 올바른 복용량을 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidDosage =>
      isEnglish ? 'Enter a valid dose.' : '0보다 큰 올바른 복용량을 입력해주세요.';
  // 함수이름: dosageUnitLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Tablet" 문구를 제공한다.
  // 매개변수:
  // - unit (String): 복용량을 표시할 단위 코드.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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

  // 함수이름: periodTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 기간" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get periodTitle => isEnglish ? 'Medication period' : '복용 기간';
  // 함수이름: startDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "시작일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get startDate => isEnglish ? 'Start' : '시작일';
  // 함수이름: endDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "종료일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get endDate => isEnglish ? 'End' : '종료일';
  // 함수이름: periodSummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "총 $days일 복용" 문구를 제공한다.
  // 매개변수:
  // - days (int): 복용 기간의 일수 또는 이를 표현한 원본 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String periodSummary(int days) => isEnglish ? '$days day(s)' : '총 $days일 복용';
  // 함수이름: slotTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시간대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get slotTitle => isEnglish ? 'When to take' : '복용 시간대';
  // 함수이름: slotDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 안내에 적힌 시간대를 모두 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get slotDescription => isEnglish
      ? 'Choose every time slot shown on the medication instructions.'
      : '복약 안내에 적힌 시간대를 모두 선택해주세요.';
  // 함수이름: slotRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시간대를 한 개 이상 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get slotRequired =>
      isEnglish ? 'Choose at least one time slot.' : '복용 시간대를 한 개 이상 선택해주세요.';
  // 함수이름: slotLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - key (String): 위젯을 구분하고 상태를 유지할 식별 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotLabel(String key) {
    return switch (key) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => key,
    };
  }

  // 함수이름: camera
  // 함수역할: 현재 언어와 입력값에 맞춰 "카메라로 촬영" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get camera => isEnglish ? 'Take photo' : '카메라로 촬영';
  // 함수이름: gallery
  // 함수역할: 현재 언어와 입력값에 맞춰 "갤러리에서 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get gallery => isEnglish ? 'Choose from gallery' : '갤러리에서 선택';
  // 함수이름: save
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보 저장" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get save => isEnglish ? 'Save medication' : '복약 정보 저장';
  // 함수이름: saving
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  // 함수이름: saved
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 정보를 저장했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saved => isEnglish ? 'Medication saved.' : '복약 정보를 저장했습니다.';
  // 함수이름: duplicate
  // 함수역할: 현재 언어와 입력값에 맞춰 "이미 추가된 약입니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get duplicate =>
      isEnglish ? 'This medication is already saved.' : '이미 추가된 약입니다.';
}
