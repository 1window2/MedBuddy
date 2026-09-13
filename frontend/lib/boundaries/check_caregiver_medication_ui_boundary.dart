// 파일명: check_caregiver_medication_ui_boundary.dart
// 역할: 연동 환자의 오늘 복약 상태와 보호자 알림 설정을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/check_caregiver_medication_control.dart';
import '../controls/manage_caregiver_patient_local_state_control.dart';
import '../controls/set_caregiver_notification_control.dart';
import '../entities/caregiver_notification_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../services/user_facing_error_message.dart';
import 'check_medication_detail_ui_boundary.dart';
import 'set_caregiver_notification_ui_boundary.dart';

// 파일명: check_caregiver_medication_ui_boundary.dart
// 역할: 연동 환자의 오늘 복약 일정과 시간대별 보호자 알림을 제공한다.

// 클래스명: CheckCaregiverMedicationUI
// 역할: 환자별 복약 완료 상태와 시간대별 보호자 알림을 담당한다.
// 주요 책임:
// - 환자별 복약 완료 상태와 시간대별 보호자 알림의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - caregiverHash (String): 환자 연결과 알림 조회의 보호자 해시.
// - patientHash (String): 연동된 환자의 계정 해시.
// - patientLabel (String?): 환자 식별에 사용할 별칭.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class CheckCaregiverMedicationUI extends StatefulWidget {
  final String caregiverHash;
  final String patientHash;
  final String? patientLabel;
  final UserSetting userSetting;
  final CheckCaregiverMedication? control;
  final SetCaregiverNotification? notificationControl;

  // 함수이름: CheckCaregiverMedicationUI
  // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - caregiverHash (String): 환자 연결과 알림 조회의 보호자 해시.
  // - patientHash (String): 연동된 환자의 계정 해시.
  // - patientLabel (String?): 환자 식별에 사용할 별칭.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (CheckCaregiverMedication?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - notificationControl (SetCaregiverNotification?): 보호자 알림 조회·저장을 처리할 컨트롤러.
  // 반환값: 입력 설정이 반영된 CheckCaregiverMedicationUI 인스턴스.
  const CheckCaregiverMedicationUI({
    super.key,
    required this.caregiverHash,
    required this.patientHash,
    this.patientLabel,
    this.userSetting = const UserSetting(),
    this.control,
    this.notificationControl,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates a patient's dose completion and per-slot caregiver reminder controls.
  // Parameters:
  // - None.
  // Returns: A new _CheckCaregiverMedicationUIState instance.
  @override
  State<CheckCaregiverMedicationUI> createState() =>
      _CheckCaregiverMedicationUIState();
}

// 클래스명: _CheckCaregiverMedicationUIState
// 역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 화면 상태를 관리한다.
// 주요 책임:
// - 초기 로딩·오류·일정 부재를 구분하고 시간대별 환자 약 목록을 표시한다.
// - 진행 화면을 띄우지 않고 환자 복약 상태와 보호자 알림을 함께 갱신한다.
// - 로컬에 저장된 환자 별칭을 읽고 표시 값이 달라진 경우 반영한다.
// 속성:
// - _slots (List<_CaregiverScheduleSlot>): 시간대별 약품과 표시 정의를 묶은 목록.
// - _control (CheckCaregiverMedication): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - _notificationControl (SetCaregiverNotification): 보호자 알림 조회·저장을 처리할 컨트롤러.
// - _lastSynchronizedAt (DateTime?): 마지막으로 환자 상태를 성공적으로 갱신한 시각.
class _CheckCaregiverMedicationUIState
    extends State<CheckCaregiverMedicationUI> {
  static const Duration _refreshInterval = Duration(seconds: 15);
  static const ManageCaregiverPatientLocalState _localStateControl =
      ManageCaregiverPatientLocalState();
  static const List<_CaregiverScheduleSlot> _slots = [
    _CaregiverScheduleSlot(
      key: 'morning',
      hour: 8,
      color: MedBuddyColors.slotMorning,
      icon: Icons.wb_sunny_outlined,
    ),
    _CaregiverScheduleSlot(
      key: 'lunch',
      hour: 12,
      color: MedBuddyColors.slotLunch,
      icon: Icons.local_cafe_outlined,
    ),
    _CaregiverScheduleSlot(
      key: 'evening',
      hour: 18,
      color: MedBuddyColors.slotEvening,
      icon: Icons.wb_twilight_outlined,
    ),
    _CaregiverScheduleSlot(
      key: 'bedtime',
      hour: 22,
      color: MedBuddyColors.slotBedtime,
      icon: Icons.nightlight_round,
    ),
  ];

  late final CheckCaregiverMedication _control;
  late final bool _ownsControl;
  late final SetCaregiverNotification _notificationControl;
  late final bool _ownsNotificationControl;
  CaregiverMedicationInfo? _medicationInfo;
  Map<String, CaregiverNotification> _notificationSettings = const {};
  Timer? _refreshTimer;
  String? _errorMessage;
  DateTime? _lastSynchronizedAt;
  String? _notificationSavingSlotKey;
  bool _isLoading = true;
  bool _isRefreshInFlight = false;
  bool _isNotificationLoading = true;
  bool _isNotificationRefreshInFlight = false;
  late String _patientLabel;

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isEnglish {
    return widget.userSetting.language.trim().toLowerCase().startsWith('en');
  }

  // 함수이름: initState
  // 함수역할: 환자 별칭·조회 컨트롤러를 준비하고 복약·알림 초기 조회와 15초 주기 갱신을 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _patientLabel = widget.patientLabel?.trim().isNotEmpty == true
        ? widget.patientLabel!.trim()
        : _localStateControl.fallbackLabel(widget.patientHash);
    _control =
        widget.control ??
        CheckCaregiverMedication(caregiverHash: widget.caregiverHash);
    _ownsNotificationControl = widget.notificationControl == null;
    _notificationControl =
        widget.notificationControl ??
        SetCaregiverNotification(caregiverHash: widget.caregiverHash);
    _requestPatientMedicationInfo();
    _requestCaregiverNotificationSettings();
    unawaited(_loadPatientLabel());
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      // 함수이름: initState.periodic callback
      // 함수역할: 진행 화면을 띄우지 않고 환자 복약 상태와 보호자 알림을 함께 갱신한다.
      // 매개변수:
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
      (_) => unawaited(_refreshCaregiverData()),
    );
  }

  // 함수이름: dispose
  // 함수역할: _refreshTimer, _control, _notificationControl 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_ownsControl) {
      _control.dispose();
    }
    if (_ownsNotificationControl) {
      _notificationControl.dispose();
    }
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자별 복약 완료 상태와 시간대별 보호자 알림 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자별 복약 완료 상태와 시간대별 보호자 알림에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final schedules =
        _medicationInfo?.todayMedicationScheduleList ??
        const <MedicationSchedule>[];
    final progress = _calculateProgress(schedules);

    return Scaffold(
      backgroundColor: MedBuddyColors.surface,
      body: Column(
        children: [
          _CaregiverScheduleHeader(
            isEnglish: _isEnglish,
            patientLabel: _patientLabel,
            completedCount: progress.completedCount,
            totalCount: progress.totalCount,
            // 함수이름: build.onBack callback
            // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onBack: () => Navigator.pop(context),
          ),
          _CaregiverSynchronizationBanner(
            isEnglish: _isEnglish,
            lastSynchronizedAt: _lastSynchronizedAt,
            hasSynchronizationError: _errorMessage != null,
            isRefreshing: _isRefreshInFlight && _isLoading,
            onRefresh: _requestPatientMedicationInfo,
          ),
          Expanded(
            child: RefreshIndicator(
              color: MedBuddyColors.primary,
              onRefresh: _requestPatientMedicationInfo,
              child: _buildBody(schedules),
            ),
          ),
        ],
      ),
    );
  }

  // 함수이름: _buildBody
  // 함수역할: 초기 로딩·오류·일정 부재를 구분하고 시간대별 환자 약 목록을 표시한다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // 반환값: 환자별 복약 완료 상태와 시간대별 보호자 알림에 쓰는 위젯 트리.
  Widget _buildBody(List<MedicationSchedule> schedules) {
    if (_isLoading && _medicationInfo == null) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }
    if (_errorMessage != null && _medicationInfo == null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.error_outline_rounded,
            color: MedBuddyColors.textMuted,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(
            _isEnglish
                ? 'Could not load the patient schedule.'
                : '환자의 복약 일정을 불러오지 못했습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: MedBuddyColors.textMuted),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: _requestPatientMedicationInfo,
            child: Text(_isEnglish ? 'Retry' : '다시 시도'),
          ),
        ],
      );
    }
    if (schedules.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
        children: [
          const Icon(
            Icons.event_available_outlined,
            color: MedBuddyColors.textLight,
            size: 58,
          ),
          const SizedBox(height: 18),
          Text(
            _isEnglish
                ? 'No medication is scheduled for today.'
                : '오늘 예정된 복약 일정이 없습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(34, 18, 34, 32),
      children: [
        for (final slot in _slots) ...[
          _CaregiverTimeSlotCard(
            slot: slot,
            isEnglish: _isEnglish,
            userSetting: widget.userSetting,
            medications: schedules
                // 함수이름: _buildBody.where callback
                // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림에 대해 `schedule.slotKeys.contains(slot.key)` 조건으로 컬렉션 항목을 판별한다.
                // 매개변수:
                // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
                // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
                .where((schedule) => schedule.slotKeys.contains(slot.key))
                .toList(growable: false),
            notificationSetting: _notificationSettings[slot.key],
            isNotificationLoading:
                _isNotificationLoading ||
                _notificationSavingSlotKey == slot.key,
            // 함수이름: _buildBody.onNotification callback
            // 함수역할: 알림 설정을 확보한 뒤 선택 시간대의 편집 창을 열고 실제 변경만 저장한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            onNotification: () => _showCaregiverNotificationPopup(slot),
            onMedicationTap: _openMedicationDetail,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // 함수이름: _refreshCaregiverData
  // 함수역할: 진행 화면을 띄우지 않고 환자 복약 상태와 보호자 알림을 함께 갱신한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _refreshCaregiverData() async {
    await Future.wait([
      _requestPatientMedicationInfo(silent: true),
      _requestCaregiverNotificationSettings(silent: true),
    ]);
  }

  // 함수이름: _loadPatientLabel
  // 함수역할: 로컬에 저장된 환자 별칭을 읽고 표시 값이 달라진 경우 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _loadPatientLabel() async {
    final label = await _localStateControl.loadLabel(
      caregiverHash: widget.caregiverHash,
      patientHash: widget.patientHash,
    );
    if (!mounted || label == _patientLabel) {
      return;
    }
    // 함수이름: _loadPatientLabel.setState callback
    // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_patientLabel = label`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _patientLabel = label);
  }

  // 함수이름: _requestPatientMedicationInfo
  // 함수역할: 중복 조회를 막으며 환자의 오늘 일정·동기화 시각·오류 상태를 갱신한다.
  // 매개변수:
  // - silent (bool): 별도 로딩 표시 없이 배경 갱신할지 여부.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestPatientMedicationInfo({bool silent = false}) async {
    if (_isRefreshInFlight) {
      return;
    }
    _isRefreshInFlight = true;
    if (mounted && !silent) {
      // Function Name: _requestPatientMedicationInfo.setState callback
      // Description: Updates the local input or request state for a patient's dose completion and per-slot caregiver reminder controls: `_isLoading = true; _errorMessage = null`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final info = await _control.requestPatientMedicationInfo(
        patientHash: widget.patientHash,
      );
      if (mounted) {
        // 함수이름: _requestPatientMedicationInfo.setState callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_medicationInfo = info; _errorMessage = null; _lastSynchronizedAt = DateTime.now()`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _medicationInfo = info;
          _errorMessage = null;
          _lastSynchronizedAt = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) {
        // 함수이름: _requestPatientMedicationInfo.setState callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_errorMessage = UserFacingErrorMessage.resolve(error, isEnglish: _isEnglish)`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _errorMessage = UserFacingErrorMessage.resolve(
            error,
            isEnglish: _isEnglish,
          );
        });
      }
    } finally {
      _isRefreshInFlight = false;
      if (mounted && !silent) {
        // Function Name: _requestPatientMedicationInfo.setState callback
        // Description: Updates the local input or request state for a patient's dose completion and per-slot caregiver reminder controls: `_isLoading = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() => _isLoading = false);
      }
    }
  }

  // 함수이름: _requestCaregiverNotificationSettings
  // 함수역할: 중복 요청을 막고 환자별 알림 설정을 조회하며 요청 시 오류를 안내한다.
  // 매개변수:
  // - showError (bool): 조회 실패를 사용자에게 바로 안내할지 여부.
  // - silent (bool): 별도 로딩 표시 없이 배경 갱신할지 여부.
  // 반환값: 성공하면 true, 실패하거나 요청을 수행하지 못하면 false로 완료되는 Future.
  Future<bool> _requestCaregiverNotificationSettings({
    bool showError = false,
    bool silent = false,
  }) async {
    if (_isNotificationRefreshInFlight) {
      return false;
    }
    _isNotificationRefreshInFlight = true;
    if (mounted && !silent) {
      // 함수이름: _requestCaregiverNotificationSettings.setState callback
      // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_isNotificationLoading = true`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isNotificationLoading = true);
    }
    try {
      final settings = await _notificationControl
          .requestCaregiverNotificationSettings(
            patientHash: widget.patientHash,
          );
      if (mounted) {
        // 함수이름: _requestCaregiverNotificationSettings.setState callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_notificationSettings = settings`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _notificationSettings = settings);
      }
      return true;
    } catch (error) {
      if (mounted && showError) {
        _showMessage(
          UserFacingErrorMessage.resolve(error, isEnglish: _isEnglish),
        );
      }
      return false;
    } finally {
      _isNotificationRefreshInFlight = false;
      if (mounted && !silent) {
        // Function Name: _requestCaregiverNotificationSettings.setState callback
        // Description: Updates the local input or request state for a patient's dose completion and per-slot caregiver reminder controls: `_isNotificationLoading = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() => _isNotificationLoading = false);
      }
    }
  }

  // 함수이름: _showCaregiverNotificationPopup
  // 함수역할: 알림 설정을 확보한 뒤 선택 시간대의 편집 창을 열고 실제 변경만 저장한다.
  // 매개변수:
  // - slot (_CaregiverScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showCaregiverNotificationPopup(
    _CaregiverScheduleSlot slot,
  ) async {
    if (_notificationSettings[slot.key] == null) {
      final loaded = await _requestCaregiverNotificationSettings(
        showError: true,
      );
      if (!loaded || !mounted) {
        return;
      }
    }

    final currentSetting =
        _notificationSettings[slot.key] ??
        CaregiverNotification(
          caregiverHash: widget.caregiverHash,
          patientHash: widget.patientHash,
          slotKey: slot.key,
        );
    if (!mounted) {
      return;
    }
    final selectedSetting =
        await SetCaregiverNotificationUI.showNotificationPopup(
          context,
          setting: currentSetting,
          language: widget.userSetting.language,
          slotLabel: slot.title(_isEnglish),
          userSetting: widget.userSetting,
        );
    if (selectedSetting == null || !mounted) {
      return;
    }
    final unchanged =
        selectedSetting.mode == currentSetting.mode &&
        selectedSetting.deadlineHour == currentSetting.deadlineHour &&
        selectedSetting.deadlineMinute == currentSetting.deadlineMinute;
    if (unchanged) {
      return;
    }
    await _saveCaregiverNotificationSetting(slot, selectedSetting);
  }

  // 함수이름: _saveCaregiverNotificationSetting
  // 함수역할: 시간대별 알림 조건·마감 시각을 저장하고 진행·성공·실패 상태를 반영한다.
  // 매개변수:
  // - slot (_CaregiverScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // - selectedSetting (CaregiverNotification): 표시하거나 편집할 복약 시간대의 알림 설정.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _saveCaregiverNotificationSetting(
    _CaregiverScheduleSlot slot,
    CaregiverNotification selectedSetting,
  ) async {
    // 함수이름: _saveCaregiverNotificationSetting.setState callback
    // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_notificationSavingSlotKey = slot.key`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _notificationSavingSlotKey = slot.key);
    try {
      final savedSetting = await _notificationControl
          .saveCaregiverNotificationSetting(
            patientHash: widget.patientHash,
            slotKey: slot.key,
            mode: selectedSetting.mode,
            deadlineHour: selectedSetting.deadlineHour,
            deadlineMinute: selectedSetting.deadlineMinute,
          );
      if (mounted) {
        // 함수이름: _saveCaregiverNotificationSetting.setState callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_notificationSettings = {..._notificationSettings, slot.key : savedSetting}`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _notificationSettings = {
            ..._notificationSettings,
            slot.key: savedSetting,
          };
        });
        _showMessage(
          _isEnglish
              ? '${slot.title(true)} notification saved.'
              : '${slot.title(false)} 알림 설정을 저장했습니다.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          UserFacingErrorMessage.resolve(error, isEnglish: _isEnglish),
        );
      }
    } finally {
      if (mounted) {
        // 함수이름: _saveCaregiverNotificationSetting.setState callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림의 입력·요청 상태를 `_notificationSavingSlotKey = null`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _notificationSavingSlotKey = null);
      }
    }
  }

  // Function Name: _showMessage
  // Description: Replaces the current snackbar with the operation result.
  // Parameters:
  // - message (String): Visible wording for the current result, error, or state.
  // Returns: None; updates state or performs the documented action.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // 함수이름: _openMedicationDetail
  // 함수역할: 복약 일정에서 상세 모델을 구성해 약 상세 화면을 연다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _openMedicationDetail(MedicationSchedule schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // 함수이름: _openMedicationDetail.builder callback
        // 함수역할: 환자별 복약 완료 상태와 시간대별 보호자 알림에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: MedicationDetail.fromMedicationSchedule(schedule),
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  // 함수이름: _calculateProgress
  // 함수역할: 약품별 시간대 완료 상태를 합산해 완료 수와 전체 복약 횟수를 계산한다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // 반환값: ({int completedCount, int totalCount}): 완료 수와 전체 복약 시간대 수.
  static ({int completedCount, int totalCount}) _calculateProgress(
    List<MedicationSchedule> schedules,
  ) {
    var completedCount = 0;
    var totalCount = 0;
    for (final schedule in schedules) {
      for (final slotKey in schedule.slotKeys) {
        totalCount += 1;
        if (schedule.isSlotCompleted(slotKey)) {
          completedCount += 1;
        }
      }
    }
    return (completedCount: completedCount, totalCount: totalCount);
  }
}

// 클래스명: _CaregiverSynchronizationBanner
// 역할: 최근 동기화 시점·지연 안내와 수동 새로고침을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 최근 동기화 시점·지연 안내와 수동 새로고침 위젯을 구성한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
// - lastSynchronizedAt (DateTime?): 마지막으로 환자 상태를 성공적으로 갱신한 시각.
// - hasSynchronizationError (bool): 이전 환자 상태 갱신이 실패했는지 여부.
// - isRefreshing (bool): 진행 중 표시를 보여줄지 여부.
class _CaregiverSynchronizationBanner extends StatelessWidget {
  final bool isEnglish;
  final DateTime? lastSynchronizedAt;
  final bool hasSynchronizationError;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  // 함수이름: _CaregiverSynchronizationBanner
  // 함수역할: 최근 동기화 시점·지연 안내와 수동 새로고침에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // - lastSynchronizedAt (DateTime?): 마지막으로 환자 상태를 성공적으로 갱신한 시각.
  // - hasSynchronizationError (bool): 이전 환자 상태 갱신이 실패했는지 여부.
  // - isRefreshing (bool): 진행 중 표시를 보여줄지 여부.
  // - onRefresh (VoidCallback): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
  // 반환값: 입력 설정이 반영된 _CaregiverSynchronizationBanner 인스턴스.
  const _CaregiverSynchronizationBanner({
    required this.isEnglish,
    required this.lastSynchronizedAt,
    required this.hasSynchronizationError,
    required this.isRefreshing,
    required this.onRefresh,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 최근 동기화 시점·지연 안내와 수동 새로고침 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 최근 동기화 시점·지연 안내와 수동 새로고침에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final isDelayed = hasSynchronizationError && lastSynchronizedAt != null;
    final color = isDelayed
        ? const Color(0xFF9A6700)
        : MedBuddyColors.primaryDark;
    final backgroundColor = isDelayed
        ? const Color(0xFFFFF4D6)
        : MedBuddyColors.successSurface;

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 9, 12, 9),
      child: Row(
        children: [
          Icon(
            isDelayed ? Icons.sync_problem_rounded : Icons.sync_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isRefreshing)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: MedBuddyColors.primary,
                ),
              ),
            )
          else
            IconButton(
              tooltip: isEnglish ? 'Refresh' : '새로고침',
              onPressed: onRefresh,
              icon: Icon(Icons.refresh_rounded, color: color),
            ),
        ],
      ),
    );
  }

  // 함수이름: _message
  // 함수역할: 동기화 여부와 마지막 갱신 이후 경과 시간을 조합해 상태 문구를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _message() {
    if (lastSynchronizedAt == null) {
      return isEnglish
          ? 'Loading the patient\'s latest medication status.'
          : '환자의 최신 복약 상태를 불러오는 중입니다.';
    }

    final elapsed = DateTime.now().difference(lastSynchronizedAt!);
    final elapsedLabel = _elapsedLabel(elapsed);
    if (hasSynchronizationError) {
      return isEnglish
          ? 'Sync delayed · Last updated $elapsedLabel'
          : '동기화 지연 · 마지막 업데이트 $elapsedLabel';
    }
    return isEnglish
        ? 'Patient check status · Updated $elapsedLabel'
        : '환자가 체크한 복약 상태 · $elapsedLabel 업데이트';
  }

  // 함수이름: _elapsedLabel
  // 함수역할: 10초 미만은 방금으로, 그 외에는 초·분·시간 단위로 경과 시간을 표시한다.
  // 매개변수:
  // - elapsed (Duration): 마지막 동기화 이후 경과 시간.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _elapsedLabel(Duration elapsed) {
    if (elapsed.inSeconds < 10) {
      return isEnglish ? 'just now' : '방금';
    }
    if (elapsed.inMinutes < 1) {
      return isEnglish
          ? '${elapsed.inSeconds}s ago'
          : '${elapsed.inSeconds}초 전';
    }
    if (elapsed.inHours < 1) {
      return isEnglish
          ? '${elapsed.inMinutes}m ago'
          : '${elapsed.inMinutes}분 전';
    }
    return isEnglish ? '${elapsed.inHours}h ago' : '${elapsed.inHours}시간 전';
  }
}

// 클래스명: _CaregiverScheduleHeader
// 역할: 연동 환자 이름과 복약 완료 수·진행률을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 연동 환자 이름과 복약 완료 수·진행률 위젯을 구성한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
// - patientLabel (String): 환자 식별에 사용할 별칭.
// - completedCount (int): 완료한 복약 횟수.
// - totalCount (int): 예정된 전체 복약 횟수 또는 처리 항목 수.
class _CaregiverScheduleHeader extends StatelessWidget {
  final bool isEnglish;
  final String patientLabel;
  final int completedCount;
  final int totalCount;
  final VoidCallback onBack;

  // 함수이름: _CaregiverScheduleHeader
  // 함수역할: 연동 환자 이름과 복약 완료 수·진행률에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // - patientLabel (String): 환자 식별에 사용할 별칭.
  // - completedCount (int): 완료한 복약 횟수.
  // - totalCount (int): 예정된 전체 복약 횟수 또는 처리 항목 수.
  // - onBack (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _CaregiverScheduleHeader 인스턴스.
  const _CaregiverScheduleHeader({
    required this.isEnglish,
    required this.patientLabel,
    required this.completedCount,
    required this.totalCount,
    required this.onBack,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 연동 환자 이름과 복약 완료 수·진행률 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 연동 환자 이름과 복약 완료 수·진행률에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        24,
        18,
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: isEnglish ? 'Back' : '뒤로가기',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnglish
                          ? "Patient's Medication Schedule"
                          : '환자 오늘의 복약 일정',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      patientLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
            decoration: BoxDecoration(
              color: MedBuddyColors.primaryDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEnglish ? 'Medication progress' : '복용 진행률',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$completedCount/$totalCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white,
                  backgroundColor: MedBuddyColors.progressTrack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _CaregiverTimeSlotCard
// 역할: 시간대별 환자 약 목록과 보호자 알림 설정을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 시간대별 환자 약 목록과 보호자 알림 설정 위젯을 구성한다.
// 속성:
// - slot (_CaregiverScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - medications (List<MedicationSchedule>): 조회·선택·정렬·표시에 사용할 약품 목록.
class _CaregiverTimeSlotCard extends StatelessWidget {
  final _CaregiverScheduleSlot slot;
  final bool isEnglish;
  final UserSetting userSetting;
  final List<MedicationSchedule> medications;
  final CaregiverNotification? notificationSetting;
  final bool isNotificationLoading;
  final VoidCallback onNotification;
  final ValueChanged<MedicationSchedule> onMedicationTap;

  // 함수이름: _CaregiverTimeSlotCard
  // 함수역할: 시간대별 환자 약 목록과 보호자 알림 설정에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - slot (_CaregiverScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - medications (List<MedicationSchedule>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // - notificationSetting (CaregiverNotification?): 현재 또는 사용자가 선택한 시간대 알림 설정.
  // - isNotificationLoading (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - onNotification (VoidCallback): 해당 시간대의 알림 설정을 여는 콜백.
  // - onMedicationTap (ValueChanged<MedicationSchedule>): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // 반환값: 입력 설정이 반영된 _CaregiverTimeSlotCard 인스턴스.
  const _CaregiverTimeSlotCard({
    required this.slot,
    required this.isEnglish,
    required this.userSetting,
    required this.medications,
    required this.notificationSetting,
    required this.isNotificationLoading,
    required this.onNotification,
    required this.onMedicationTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 시간대별 환자 약 목록과 보호자 알림 설정 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 시간대별 환자 약 목록과 보호자 알림 설정에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: slot.color,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(slot.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.title(isEnglish),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        userSetting.formatTime(slot.hour, 0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 42,
                  child: isNotificationLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : IconButton(
                          key: ValueKey('caregiver-notification-${slot.key}'),
                          tooltip: isEnglish
                              ? '${slot.title(true)} notification settings'
                              : '${slot.title(false)} 알림 설정',
                          onPressed: onNotification,
                          style:
                              notificationSetting?.notificationEnabled == true
                              ? IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.redAccent,
                                )
                              : null,
                          icon: Icon(
                            notificationSetting?.notificationEnabled == true
                                ? Icons.notifications_active
                                : Icons.notifications_none_outlined,
                            color:
                                notificationSetting?.notificationEnabled == true
                                ? Colors.redAccent
                                : Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (medications.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Text(
                isEnglish
                    ? 'No medication for this time'
                    : '이 시간에 복용할 약이 없습니다.',
                style: const TextStyle(color: MedBuddyColors.textLight),
              ),
            )
          else
            for (var index = 0; index < medications.length; index++) ...[
              _CaregiverMedicationRow(
                schedule: medications[index],
                slotKey: slot.key,
                isEnglish: isEnglish,
                // 함수이름: build.onTap callback
                // 함수역할: 시간대별 환자 약 목록과 보호자 알림 설정에서 캡처된 작업 `onMedicationTap(medications[index])`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onTap: () => onMedicationTap(medications[index]),
              ),
              if (index < medications.length - 1)
                const Divider(height: 1, color: MedBuddyColors.divider),
            ],
        ],
      ),
    );
  }
}

// 클래스명: _CaregiverMedicationRow
// 역할: 환자 약 한 건의 복용량·체크 상태와 상세 진입을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 환자 약 한 건의 복용량·체크 상태와 상세 진입 위젯을 구성한다.
// 속성:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
// - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _CaregiverMedicationRow extends StatelessWidget {
  final MedicationSchedule schedule;
  final String slotKey;
  final bool isEnglish;
  final VoidCallback onTap;

  // 함수이름: _CaregiverMedicationRow
  // 함수역할: 환자 약 한 건의 복용량·체크 상태와 상세 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _CaregiverMedicationRow 인스턴스.
  const _CaregiverMedicationRow({
    required this.schedule,
    required this.slotKey,
    required this.isEnglish,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 약 한 건의 복용량·체크 상태와 상세 진입 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 약 한 건의 복용량·체크 상태와 상세 진입에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final isCompleted = schedule.isSlotCompleted(slotKey);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        child: Row(
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
              color: isCompleted
                  ? MedBuddyColors.primary
                  : MedBuddyColors.outline,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.displayNameForLanguage(isEnglish ? 'en' : 'ko'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCompleted
                          ? MedBuddyColors.textLight
                          : MedBuddyColors.textStrong,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      decoration: isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _dosageLabel(schedule, isEnglish),
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MedicationThumbnail(schedule: schedule),
          ],
        ),
      ),
    );
  }

  // 함수이름: _dosageLabel
  // 함수역할: 일정 모델이 제공하는 언어별 1회 복용량 표기를 사용한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  static String _dosageLabel(MedicationSchedule schedule, bool isEnglish) {
    return schedule.dosageLabelForLanguage(isEnglish ? 'en' : 'ko');
  }
}

// Class Name: _MedicationThumbnail
// Role: Represents a medication thumbnail with missing-image and loading-failure fallbacks.
// Responsibilities:
// - Composes a medication thumbnail with missing-image and loading-failure fallbacks using the display values and actions supplied by its parent.
// Attributes:
// - schedule (MedicationSchedule): Medication schedule containing name, dosage, days, slots, and completion state.
class _MedicationThumbnail extends StatelessWidget {
  final MedicationSchedule schedule;

  // 함수이름: _MedicationThumbnail
  // 함수역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: 입력 설정이 반영된 _MedicationThumbnail 인스턴스.
  const _MedicationThumbnail({required this.schedule});

  // Function Name: build
  // Description: Renders a medication thumbnail with missing-image and loading-failure fallbacks from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a medication thumbnail with missing-image and loading-failure fallbacks.
  @override
  Widget build(BuildContext context) {
    final imageUrl = safeMedicationImageUrl(schedule.imageUrl);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MedBuddyColors.imageAccent, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isEmpty
          ? const Icon(
              Icons.image_not_supported_outlined,
              color: MedBuddyColors.textLight,
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              // 함수이름: build.errorBuilder callback
              // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
              // 매개변수:
              // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
              // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
              // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
              // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
              errorBuilder: (_, _, _) => const Icon(
                Icons.image_not_supported_outlined,
                color: MedBuddyColors.textLight,
              ),
            ),
    );
  }
}

// 클래스명: _CaregiverScheduleSlot
// 역할: 복약 시간대 키·기본 시각·색상·아이콘을 담당한다.
// 주요 책임:
// - 시간대 기본 시각을 두 자리 시와 분으로 표시한다.
// - 시간대 키를 언어별 이름으로 변환하고 알 수 없는 키에는 일정 제목을 사용한다.
// 속성:
// - key (String): 복약 시간대를 구분하는 식별 문자열.
// - hour (int): 24시간제 시 값.
// - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
class _CaregiverScheduleSlot {
  final String key;
  final int hour;
  final Color color;
  final IconData icon;

  // 함수이름: _CaregiverScheduleSlot
  // 함수역할: 복약 시간대 키·기본 시각·색상·아이콘 관련 값을 _CaregiverScheduleSlot 인스턴스에 담는다.
  // 매개변수:
  // - key (String): 복약 시간대를 구분하는 식별 문자열.
  // - hour (int): 24시간제 시 값.
  // - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // 반환값: 입력 설정이 반영된 _CaregiverScheduleSlot 인스턴스.
  const _CaregiverScheduleSlot({
    required this.key,
    required this.hour,
    required this.color,
    required this.icon,
  });

  // 함수이름: timeLabel
  // 함수역할: 시간대 기본 시각을 두 자리 시와 분으로 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get timeLabel => '${hour.toString().padLeft(2, '0')}:00';

  // 함수이름: title
  // 함수역할: 시간대 키를 언어별 이름으로 변환하고 알 수 없는 키에는 일정 제목을 사용한다.
  // 매개변수:
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String title(bool isEnglish) {
    return switch (key) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Schedule' : '복약 일정',
    };
  }
}
