// 파일명: manage_user_setting_ui_boundary.dart
// 역할: 접근성·알림·실험 기능·계정 보안 설정을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../services/tts_service.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/app_version_label.dart';
import 'set_notification_ui_boundary.dart';

// 함수이름: SettingPreviewSpeaker
// 함수역할: 설정된 언어·속도로 미리보기 문장을 재생하고 완료 콜백을 지원하는 계약이다.
// 매개변수:
// - text (String): 현재 언어와 읽기 속도로 재생할 미리보기 문장.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onComplete (void Function()?): 음성 재생 완료 시 상태를 해제할 선택적 콜백.
// 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
typedef SettingPreviewSpeaker =
    Future<void> Function(
      String text,
      UserSetting userSetting, {
      void Function()? onComplete,
    });
// 함수이름: SettingPreviewStopper
// 함수역할: 진행 중인 설정 음성 미리보기를 비동기로 중지하는 콜백 계약이다.
// 매개변수:
// - 없음.
// 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
typedef SettingPreviewStopper = Future<void> Function();
// 함수이름: ExtendedUserSettingSaver
// 함수역할: 확장된 사용자 설정을 저장하고 서버 동기화 여부를 돌려주는 콜백 계약이다.
// 매개변수:
// - setting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// 반환값: Future<UserSettingSaveResult>: 저장된 설정과 서버 동기화 성공 여부.
typedef ExtendedUserSettingSaver =
    Future<UserSettingSaveResult> Function(UserSetting setting);

// 클래스명: ManageUserSettingUI
// 역할: 접근성·기본 복약 시각·계정 보안 설정을 담당한다.
// 주요 책임:
// - 현재 저장된 설정을 초기 선택값으로 표시한다.
// - 글씨 크기와 언어 변경을 현재 설정 화면에 즉시 반영한다.
// - 저장 버튼을 통해 변경값을 ViewModel로 전달한다.
// 속성:
// - initialSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - authenticationControl (AuthenticationControl): 인증·계정·다중 인증 상태와 명령 제공자.
// - onSignOutRequested (Future<void> Function()?): 현재 계정을 로그아웃할 콜백.
// - onDeleteAccountRequested (Future<void> Function()?): 확인된 계정 삭제를 수행할 콜백.
class ManageUserSettingUI extends StatefulWidget {
  final UserSetting initialSetting;
  final AuthenticationControl authenticationControl;
  final Future<void> Function()? onSignOutRequested;
  final Future<void> Function()? onDeleteAccountRequested;
  final SettingPreviewSpeaker? previewSpeaker;
  final SettingPreviewStopper? previewStopper;
  final Future<void> Function(bool enabled)?
  onMultiPillIdentificationLabSettingSaveRequested;
  final ExtendedUserSettingSaver? onExtendedSettingSaveRequested;
  final VoidCallback? onMedicationScheduleRequested;
  final Future<void> Function()? onDeviceNotificationSettingsRequested;
  final Future<UserSettingSaveResult> Function({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  })
  onSettingSaveRequested;

  // 함수이름: ManageUserSettingUI
  // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - initialSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - authenticationControl (AuthenticationControl): 인증·계정·다중 인증 상태와 명령 제공자.
  // - onSettingSaveRequested (Future<UserSettingSaveResult> Function({required String fontSizeOption, required String readingSpeedOption, required String language})): 편집한 사용자 설정을 저장하고 동기화 결과를 반환할 콜백.
  // - onSignOutRequested (Future<void> Function()?): 현재 계정을 로그아웃할 콜백.
  // - onDeleteAccountRequested (Future<void> Function()?): 확인된 계정 삭제를 수행할 콜백.
  // - previewSpeaker (SettingPreviewSpeaker?): 미리보기 문장을 현재 설정으로 읽는 함수.
  // - previewStopper (SettingPreviewStopper?): 진행 중인 음성 미리보기를 중지하는 함수.
  // - onMultiPillIdentificationLabSettingSaveRequested (Future<void> Function(bool enabled)?): 여러 알약 식별 실험 기능의 활성 여부를 저장할 콜백.
  // - onExtendedSettingSaveRequested (ExtendedUserSettingSaver?): 편집한 사용자 설정을 저장하고 동기화 결과를 반환할 콜백.
  // - onMedicationScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
  // - onDeviceNotificationSettingsRequested (Future<void> Function()?): 운영체제의 앱 알림 설정을 여는 콜백.
  // 반환값: 입력 설정이 반영된 ManageUserSettingUI 인스턴스.
  const ManageUserSettingUI({
    super.key,
    required this.initialSetting,
    required this.authenticationControl,
    required this.onSettingSaveRequested,
    this.onSignOutRequested,
    this.onDeleteAccountRequested,
    this.previewSpeaker,
    this.previewStopper,
    this.onMultiPillIdentificationLabSettingSaveRequested,
    this.onExtendedSettingSaveRequested,
    this.onMedicationScheduleRequested,
    this.onDeviceNotificationSettingsRequested,
  });

  // 함수이름: createState
  // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _ManageUserSettingUIState 인스턴스.
  @override
  State<ManageUserSettingUI> createState() => _ManageUserSettingUIState();
}

// 클래스명: _SettingSection
// 역할: 설정 하위 화면의 현재 분류를 담당한다.
// 주요 책임:
// - 설정 하위 화면의 현재 분류에서 지원하는 선택지를 열거하고 구분한다: overview, medicationAndNotifications, displayAndVoice, laboratory, account.
enum _SettingSection {
  overview,
  medicationAndNotifications,
  displayAndVoice,
  laboratory,
  account,
}

// 클래스명: _ManageUserSettingUIState
// 역할: 접근성·기본 복약 시각·계정 보안 설정의 화면 상태를 관리한다.
// 주요 책임:
// - 글씨 크기·읽기 속도·언어·시간 형식과 음성 미리보기를 배치한다.
// - 여러 알약 식별 실험 기능의 사용 여부를 표시한다.
// - 계정 요약과 지원되는 MFA·로그아웃·계정 삭제 명령을 표시한다.
// 속성:
// - _fontSize (String): 기준 글씨 크기 또는 선택한 크기 옵션.
// - _readingSpeed (String): 읽어주기에 사용할 음성 속도 옵션.
// - _language (String): 화면 문구를 선택할 언어 코드.
// - _languageMode (String): 기기 언어 따르기 또는 명시 언어 선택 값.
class _ManageUserSettingUIState extends State<ManageUserSettingUI> {
  late String _fontSize;
  late String _readingSpeed;
  late String _language;
  late String _languageMode;
  late String _timeFormat;
  late bool _medicationNotificationsEnabled;
  late bool _caregiverNotificationsEnabled;
  late bool _chatNotificationsEnabled;
  late String _notificationDetailMode;
  late String _defaultMorningTime;
  late String _defaultLunchTime;
  late String _defaultEveningTime;
  late String _defaultBedtime;
  late bool _multiPillIdentificationLabEnabled;
  bool _isSaving = false;
  bool _isPreviewSpeaking = false;
  int _voicePreviewRequestId = 0;
  TTSService? _ownedTtsService;
  _SettingSection _selectedSection = _SettingSection.overview;

  // 함수이름: initState
  // 함수역할: 현재 설정을 수정용 필드에 복사하고 주입된 음성 재생기가 없으면 TTS를 준비한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialSetting.fontSizeOption;
    _readingSpeed = widget.initialSetting.readingSpeedOption;
    _language = widget.initialSetting.language == 'en' ? 'en' : 'ko';
    _languageMode = widget.initialSetting.languageMode;
    _timeFormat = widget.initialSetting.timeFormat;
    _medicationNotificationsEnabled =
        widget.initialSetting.medicationNotificationsEnabled;
    _caregiverNotificationsEnabled =
        widget.initialSetting.caregiverNotificationsEnabled;
    _chatNotificationsEnabled = widget.initialSetting.chatNotificationsEnabled;
    _notificationDetailMode = widget.initialSetting.notificationDetailMode;
    _defaultMorningTime = widget.initialSetting.defaultMorningTime;
    _defaultLunchTime = widget.initialSetting.defaultLunchTime;
    _defaultEveningTime = widget.initialSetting.defaultEveningTime;
    _defaultBedtime = widget.initialSetting.defaultBedtime;
    _multiPillIdentificationLabEnabled =
        widget.initialSetting.multiPillIdentificationLabEnabled;
    if (widget.previewSpeaker == null) {
      _ownedTtsService = TTSService();
    }
  }

  // 함수이름: dispose
  // 함수역할: ownedTtsService 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    final ownedTtsService = _ownedTtsService;
    if (ownedTtsService != null) {
      unawaited(ownedTtsService.stop());
    }
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 접근성·기본 복약 시각·계정 보안 설정 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _SettingText(_language);
    final draftSetting = widget.initialSetting.copyWith(
      fontSize: UserSetting.fontSizeFromOption(_fontSize),
      readingSpeed: UserSetting.readingSpeedFromOption(_readingSpeed),
      language: _language,
      languageMode: _languageMode,
      timeFormat: _timeFormat,
      medicationNotificationsEnabled: _medicationNotificationsEnabled,
      caregiverNotificationsEnabled: _caregiverNotificationsEnabled,
      chatNotificationsEnabled: _chatNotificationsEnabled,
      notificationDetailMode: _notificationDetailMode,
      defaultMorningTime: _defaultMorningTime,
      defaultLunchTime: _defaultLunchTime,
      defaultEveningTime: _defaultEveningTime,
      defaultBedtime: _defaultBedtime,
      multiPillIdentificationLabEnabled: _multiPillIdentificationLabEnabled,
    );
    final platformMediaQuery = MediaQueryData.fromView(View.of(context));
    final systemTextScale = platformMediaQuery.textScaler.scale(16) / 16;
    final selectedTextScale = draftSetting.resolveTextScale(systemTextScale);
    final mediaQuery = MediaQuery.of(context);
    final contentScale = draftSetting.contentTextScale;
    final accountPresentation = _resolveAccountPresentation(text);

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(selectedTextScale),
      ),
      child: PopScope<void>(
        canPop: _selectedSection == _SettingSection.overview,
        // 함수이름: build.onPopInvokedWithResult callback
        // 함수역할: 음성 설정에서 나올 때 미리보기를 중지하고 설정 개요를 선택한다.
        // 매개변수:
        // - didPop (bool): 탐색 프레임워크가 이미 화면을 닫았는지 여부.
        // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _showSettingsOverview();
          }
        },
        child: Scaffold(
          backgroundColor: MedBuddyColors.pageBackground,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 26, 40, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _SettingsBackButton(
                          tooltip: text.back,
                          onTap: _handleBackRequested,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey(_selectedSection),
                        padding: const EdgeInsets.fromLTRB(40, 22, 40, 24),
                        child: _buildSelectedSection(
                          text: text,
                          contentScale: contentScale,
                          accountPresentation: accountPresentation,
                        ),
                      ),
                    ),
                    if (_selectedSection ==
                            _SettingSection.medicationAndNotifications ||
                        _selectedSection == _SettingSection.displayAndVoice ||
                        _selectedSection == _SettingSection.laboratory)
                      _SettingSaveFooter(
                        text: text,
                        isSaving: _isSaving,
                        onSaveRequested: _handleSaveRequested,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildSelectedSection
  // 함수역할: 설정 홈과 각 설정 영역을 동일한 상태값으로 전환해 저장 전 선택을 유지한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - contentScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - accountPresentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  Widget _buildSelectedSection({
    required _SettingText text,
    required double contentScale,
    required _AccountPresentation accountPresentation,
  }) {
    return switch (_selectedSection) {
      _SettingSection.overview => _SettingsOverview(
        text: text,
        accountPresentation: accountPresentation,
        medicationAndNotificationSummary: text.medicationAndNotificationSummary(
          medicationEnabled: _medicationNotificationsEnabled,
          caregiverEnabled: _caregiverNotificationsEnabled,
          chatEnabled: _chatNotificationsEnabled,
        ),
        displayAndVoiceSummary: text.displayAndVoiceSummary(
          fontSize: _fontSize,
          readingSpeed: _readingSpeed,
          languageMode: _languageMode,
        ),
        laboratorySummary: text.laboratorySummary(
          multiPillIdentificationEnabled: _multiPillIdentificationLabEnabled,
        ),
        // 함수이름: _buildSelectedSection.onSectionSelected callback
        // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _selectedSection = section)`을 실행한다.
        // 매개변수:
        // - section (콜백 계약에서 추론): 이동할 사용자 설정 분류.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onSectionSelected: (section) {
          // 함수이름: _buildSelectedSection.setState callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_selectedSection = section`로 갱신한다.
          // 매개변수:
          // - 없음.
          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
          setState(() => _selectedSection = section);
        },
      ),
      _SettingSection.medicationAndNotifications =>
        _buildMedicationAndNotificationSettings(text),
      _SettingSection.displayAndVoice => _buildDisplayAndVoiceSettings(
        text,
        contentScale,
      ),
      _SettingSection.laboratory => _buildLaboratorySettings(text),
      _SettingSection.account => _buildAccountSettings(
        text,
        accountPresentation,
      ),
    };
  }

  // 함수이름: _buildMedicationAndNotificationSettings
  // 함수역할: 전체 알림 정책, 신규 일정 기본 시각과 잠금 화면 공개 범위를 구성한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  Widget _buildMedicationAndNotificationSettings(_SettingText text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.medicationAndNotificationsTitle),
        const SizedBox(height: 24),
        _SettingToggle(
          switchKey: const ValueKey('medicationNotificationsSwitch'),
          title: text.medicationNotificationsTitle,
          description: text.medicationNotificationsDescription,
          enabled: _medicationNotificationsEnabled,
          // 함수이름: _buildMedicationAndNotificationSettings.onChanged callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _medicationNotificationsEnabled = enabled)`을 실행한다.
          // 매개변수:
          // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onChanged: (enabled) =>
              // 함수이름: _buildMedicationAndNotificationSettings.setState callback
              // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_medicationNotificationsEnabled = enabled`로 갱신한다.
              // 매개변수:
              // - 없음.
              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
              setState(() => _medicationNotificationsEnabled = enabled),
        ),
        const SizedBox(height: 12),
        _SettingToggle(
          switchKey: const ValueKey('caregiverNotificationsSwitch'),
          title: text.caregiverNotificationsTitle,
          description: text.caregiverNotificationsDescription,
          enabled: _caregiverNotificationsEnabled,
          // 함수이름: _buildMedicationAndNotificationSettings.onChanged callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _caregiverNotificationsEnabled = enabled)`을 실행한다.
          // 매개변수:
          // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onChanged: (enabled) =>
              // 함수이름: _buildMedicationAndNotificationSettings.setState callback
              // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_caregiverNotificationsEnabled = enabled`로 갱신한다.
              // 매개변수:
              // - 없음.
              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
              setState(() => _caregiverNotificationsEnabled = enabled),
        ),
        const SizedBox(height: 12),
        _SettingToggle(
          switchKey: const ValueKey('chatNotificationsSwitch'),
          title: text.chatNotificationsTitle,
          description: text.chatNotificationsDescription,
          enabled: _chatNotificationsEnabled,
          // 함수이름: _buildMedicationAndNotificationSettings.onChanged callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _chatNotificationsEnabled = enabled)`을 실행한다.
          // 매개변수:
          // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onChanged: (enabled) =>
              // 함수이름: _buildMedicationAndNotificationSettings.setState callback
              // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_chatNotificationsEnabled = enabled`로 갱신한다.
              // 매개변수:
              // - 없음.
              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
              setState(() => _chatNotificationsEnabled = enabled),
        ),
        const SizedBox(height: 18),
        _SettingsActionTile(
          icon: Icons.notifications_active_outlined,
          title: text.deviceNotificationSettingsTitle,
          description: text.deviceNotificationSettingsDescription,
          onTap: _openDeviceNotificationSettings,
        ),
        const SizedBox(height: 32),
        _SettingFieldTitle(text.defaultMedicationTimeTitle),
        const SizedBox(height: 8),
        Text(
          text.defaultMedicationTimeDescription,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _DefaultMedicationTimePanel(
          text: text,
          userSetting: _draftSetting,
          morningTime: _defaultMorningTime,
          lunchTime: _defaultLunchTime,
          eveningTime: _defaultEveningTime,
          bedtime: _defaultBedtime,
          onTimeRequested: _selectDefaultMedicationTime,
        ),
        const SizedBox(height: 14),
        _SettingsActionTile(
          icon: Icons.schedule_outlined,
          title: text.detailedScheduleSettingsTitle,
          description: text.detailedScheduleSettingsDescription,
          onTap: widget.onMedicationScheduleRequested,
        ),
        const SizedBox(height: 32),
        _SettingFieldTitle(text.notificationPrivacyTitle),
        const SizedBox(height: 8),
        Text(
          text.notificationPrivacyDescription,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _StackedOptionList(
          options: [
            _SettingOption(value: 'full', label: text.notificationPrivacyFull),
            _SettingOption(
              value: 'type_only',
              label: text.notificationPrivacyTypeOnly,
            ),
          ],
          selectedValue: _notificationDetailMode,
          // 함수이름: _buildMedicationAndNotificationSettings.onSelected callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _notificationDetailMode = value)`을 실행한다.
          // 매개변수:
          // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onSelected: (value) =>
              // 함수이름: _buildMedicationAndNotificationSettings.setState callback
              // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_notificationDetailMode = value`로 갱신한다.
              // 매개변수:
              // - 없음.
              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
              setState(() => _notificationDetailMode = value),
        ),
      ],
    );
  }

  // 함수이름: _buildDisplayAndVoiceSettings
  // 함수역할: 글씨 크기·읽기 속도·언어·시간 형식과 음성 미리보기를 배치한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - contentScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  Widget _buildDisplayAndVoiceSettings(_SettingText text, double contentScale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.displayAndVoiceTitle),
        const SizedBox(height: 28),
        _SettingFieldTitle(text.fontSizeTitle),
        const SizedBox(height: 16),
        _OptionRow(
          options: [
            _SettingOption(
              value: 'small',
              label: text.small,
              labelFontSize: 14,
            ),
            _SettingOption(
              value: 'medium',
              label: text.medium,
              labelFontSize: 17,
            ),
            _SettingOption(
              value: 'large',
              label: text.large,
              labelFontSize: 23,
            ),
          ],
          selectedValue: _fontSize,
          contentScale: contentScale,
          // 함수이름: _buildDisplayAndVoiceSettings.setState callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_fontSize = value`로 갱신한다.
          // 매개변수:
          // - 없음.
          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
          // 함수이름: _buildDisplayAndVoiceSettings.onSelected callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _fontSize = value)`을 실행한다.
          // 매개변수:
          // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onSelected: (value) => setState(() => _fontSize = value),
        ),
        const SizedBox(height: 34),
        _SettingFieldTitle(text.readingSpeedTitle),
        const SizedBox(height: 16),
        _OptionRow(
          options: [
            _SettingOption(value: 'slow', label: text.slow),
            _SettingOption(value: 'medium', label: text.medium),
            _SettingOption(value: 'fast', label: text.fast),
          ],
          selectedValue: _readingSpeed,
          contentScale: contentScale,
          // 함수이름: _buildDisplayAndVoiceSettings.onSelected callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `_selectReadingSpeed(value)`을 실행한다.
          // 매개변수:
          // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onSelected: (value) => unawaited(_selectReadingSpeed(value)),
        ),
        const SizedBox(height: 34),
        _SettingFieldTitle(text.languageTitle),
        const SizedBox(height: 16),
        _StackedOptionList(
          options: [
            _SettingOption(value: 'system', label: text.followDeviceLanguage),
            const _SettingOption(value: 'ko', label: '한국어'),
            const _SettingOption(value: 'en', label: 'English'),
          ],
          selectedValue: _languageMode,
          onSelected: _selectLanguageMode,
        ),
        const SizedBox(height: 34),
        _SettingFieldTitle(text.timeFormatTitle),
        const SizedBox(height: 16),
        _OptionRow(
          options: [
            _SettingOption(value: '12h', label: text.twelveHourTime),
            _SettingOption(value: '24h', label: text.twentyFourHourTime),
          ],
          selectedValue: _timeFormat,
          contentScale: contentScale,
          // 함수이름: _buildDisplayAndVoiceSettings.setState callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_timeFormat = value`로 갱신한다.
          // 매개변수:
          // - 없음.
          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
          // 함수이름: _buildDisplayAndVoiceSettings.onSelected callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _timeFormat = value)`을 실행한다.
          // 매개변수:
          // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onSelected: (value) => setState(() => _timeFormat = value),
        ),
        const SizedBox(height: 34),
        _PreviewPanel(
          text: text,
          fontSize: _fontSize,
          readingSpeed: _readingSpeed,
          isSpeaking: _isPreviewSpeaking,
          onVoicePreviewRequested: _toggleVoicePreview,
        ),
      ],
    );
  }

  // 함수이름: _buildLaboratorySettings
  // 함수역할: 근처 약국·복약 채팅·여러 알약 식별 실험 기능의 사용 여부를 표시한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  Widget _buildLaboratorySettings(_SettingText text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.laboratoryTitle),
        const SizedBox(height: 24),
        _ExperimentalFeatureToggle(
          switchKey: const ValueKey('multiPillIdentificationLabSwitch'),
          title: text.multiPillIdentificationLabTitle,
          description: text.multiPillIdentificationLabDescription,
          enabled: _multiPillIdentificationLabEnabled,
          // 함수이름: _buildLaboratorySettings.onChanged callback
          // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `setState(() => _multiPillIdentificationLabEnabled = enabled)`을 실행한다.
          // 매개변수:
          // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onChanged: (enabled) =>
              // 함수이름: _buildLaboratorySettings.setState callback
              // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_multiPillIdentificationLabEnabled = enabled`로 갱신한다.
              // 매개변수:
              // - 없음.
              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
              setState(() => _multiPillIdentificationLabEnabled = enabled),
        ),
      ],
    );
  }

  // 함수이름: _buildAccountSettings
  // 함수역할: 계정 요약과 지원되는 MFA·로그아웃·계정 삭제 명령을 표시한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - accountPresentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
  // 반환값: 접근성·기본 복약 시각·계정 보안 설정에 쓰는 위젯 트리.
  Widget _buildAccountSettings(
    _SettingText text,
    _AccountPresentation accountPresentation,
  ) {
    final hasMfaSettings =
        widget.authenticationControl.phoneAuthenticationEnabled;
    final hasSignOut = widget.onSignOutRequested != null;
    final hasDeleteAccount = widget.onDeleteAccountRequested != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.accountTitle),
        const SizedBox(height: 24),
        _AccountWelcomePanel(presentation: accountPresentation, compact: true),
        if (hasMfaSettings) ...[
          const SizedBox(height: 18),
          ListenableBuilder(
            listenable: widget.authenticationControl,
            // 함수이름: _buildAccountSettings.builder callback
            // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
            // 매개변수:
            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
            // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
            builder: (context, _) => _MfaSettingsPanel(
              enabled: widget.authenticationControl.hasEnrolledSmsMfa,
              available: widget.authenticationControl.canEnrollSmsMfa,
              onEnrollRequested: _showMfaEnrollment,
            ),
          ),
        ],
        if (hasSignOut) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _handleSignOutRequested,
              icon: const Icon(Icons.logout),
              label: Text(text.signOut),
            ),
          ),
        ],
        if (hasDeleteAccount) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: MedBuddyColors.danger,
                side: const BorderSide(color: MedBuddyColors.danger),
              ),
              onPressed: _isSaving ? null : _confirmAccountDeletion,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(text.deleteAccount),
            ),
          ),
        ],
        if (!hasMfaSettings && !hasSignOut && !hasDeleteAccount) ...[
          const SizedBox(height: 18),
          Text(
            text.noAccountActions,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // 함수이름: _resolveAccountPresentation
  // 함수역할: 이름 또는 이메일 앞부분으로 인사말을 만들고 계정 종류에 따라 마스킹된 식별 정보를 선택한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: _AccountPresentation: 이름을 반영한 인사말과 마스킹된 계정 표시.
  _AccountPresentation _resolveAccountPresentation(_SettingText text) {
    final control = widget.authenticationControl;
    final displayName = control.signedInDisplayName;
    final email = control.signedInEmail ?? control.session?.email;
    final phoneNumber = control.signedInPhoneNumber;
    final accountName = displayName != null && displayName.isNotEmpty
        ? displayName
        : email != null && email.isNotEmpty
        ? email.split('@').first
        : text.defaultUserName;

    final detail = control.isAnonymous
        ? text.guestAccount
        : email != null && email.isNotEmpty
        ? _maskEmail(email)
        : phoneNumber != null && phoneNumber.isNotEmpty
        ? _maskPhoneNumber(phoneNumber)
        : control.session?.authenticated == false
        ? text.localDemoAccount
        : text.signedInAccount;
    return _AccountPresentation(
      greeting: text.welcome(accountName),
      detail: detail,
    );
  }

  // 함수이름: _maskEmail
  // 함수역할: 이메일 아이디의 앞 한두 글자와 도메인만 남기고 나머지를 가린다.
  // 매개변수:
  // - email (String): 계정 표시에 사용할 이메일 주소.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) {
      return email;
    }
    final localPart = email.substring(0, atIndex);
    final visibleLength = localPart.length <= 2 ? 1 : 2;
    return '${localPart.substring(0, visibleLength)}***${email.substring(atIndex)}';
  }

  // 함수이름: _maskPhoneNumber
  // 함수역할: 숫자 7자리 이상인 전화번호의 끝 4자리 앞 세 자리를 가린다.
  // 매개변수:
  // - phoneNumber (String): 계정 표시에 사용할 전화번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _maskPhoneNumber(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      return phoneNumber;
    }
    return '${digits.substring(0, digits.length - 7)}***${digits.substring(digits.length - 4)}';
  }

  // 함수이름: _handleBackRequested
  // 함수역할: 설정 개요에서는 화면을 닫고 하위 설정에서는 개요로 돌아간다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _handleBackRequested() {
    if (_selectedSection == _SettingSection.overview) {
      Navigator.maybePop(context);
      return;
    }
    _showSettingsOverview();
  }

  // 함수이름: _showSettingsOverview
  // 함수역할: 음성 설정에서 나올 때 미리보기를 중지하고 설정 개요를 선택한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showSettingsOverview() {
    if (_selectedSection == _SettingSection.displayAndVoice) {
      unawaited(_stopVoicePreview());
    }
    // 함수이름: _showSettingsOverview.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_selectedSection = _SettingSection.overview`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _selectedSection = _SettingSection.overview);
  }

  // 함수이름: _draftSetting
  // 함수역할: 기존 설정의 나머지 값은 유지하면서 현재 편집 중인 표시·알림·실험 값을 복사한다.
  // 매개변수:
  // - 없음.
  // 반환값: UserSetting: 현재 편집 중인 설정 사본.
  UserSetting get _draftSetting => widget.initialSetting.copyWith(
    fontSize: UserSetting.fontSizeFromOption(_fontSize),
    readingSpeed: UserSetting.readingSpeedFromOption(_readingSpeed),
    language: _language,
    languageMode: _languageMode,
    timeFormat: _timeFormat,
    medicationNotificationsEnabled: _medicationNotificationsEnabled,
    caregiverNotificationsEnabled: _caregiverNotificationsEnabled,
    chatNotificationsEnabled: _chatNotificationsEnabled,
    notificationDetailMode: _notificationDetailMode,
    defaultMorningTime: _defaultMorningTime,
    defaultLunchTime: _defaultLunchTime,
    defaultEveningTime: _defaultEveningTime,
    defaultBedtime: _defaultBedtime,
    multiPillIdentificationLabEnabled: _multiPillIdentificationLabEnabled,
  );

  // 함수이름: _selectLanguageMode
  // 함수역할: 선택한 언어 모드를 즉시 현재 설정 화면의 표시 언어에 반영한다.
  // 매개변수:
  // - languageMode (String): 기기 언어 따르기 또는 명시 언어 선택 값.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _selectLanguageMode(String languageMode) {
    // 함수이름: _selectLanguageMode.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_languageMode = languageMode; _language = AppLanguageControl.resolveLanguage(languageMode)`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _languageMode = languageMode;
      _language = AppLanguageControl.resolveLanguage(languageMode);
    });
  }

  // 함수이름: _selectDefaultMedicationTime
  // 함수역할: 기존 복약 알림과 같은 시간 선택기를 사용해 신규 일정 기본 시각을 바꾼다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _selectDefaultMedicationTime(String slotKey) async {
    final currentValue = _draftSetting.defaultTimeForSlot(slotKey);
    final initialTime = _parseTime(currentValue);
    final selectedTime = await SetNotificationUI.showNotificationPopup(
      context,
      slotTitle: _SettingText(_language).defaultTimeLabel(slotKey),
      initialTime: initialTime,
      language: _language,
    );
    if (!mounted || selectedTime == null) {
      return;
    }
    final formattedTime =
        '${selectedTime.hour.toString().padLeft(2, '0')}:'
        '${selectedTime.minute.toString().padLeft(2, '0')}';
    // 함수이름: _selectDefaultMedicationTime.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_defaultMorningTime = formattedTime; _defaultLunchTime = formattedTime; _defaultEveningTime = formattedTime`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      switch (slotKey) {
        case 'morning':
          _defaultMorningTime = formattedTime;
          break;
        case 'lunch':
          _defaultLunchTime = formattedTime;
          break;
        case 'evening':
          _defaultEveningTime = formattedTime;
          break;
        case 'bedtime':
          _defaultBedtime = formattedTime;
          break;
      }
    });
  }

  // 함수이름: _parseTime
  // 함수역할: 시:분을 읽고 시·분 파싱 실패에는 각각 8시·0분을 사용한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: TimeOfDay: 파싱된 시·분; 각 파싱 실패에는 8시·0분 기본값 적용.
  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts.first) ?? 8 : 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  // 함수이름: _openDeviceNotificationSettings
  // 함수역할: 주입된 기기 알림 설정 열기를 실행하고 예외 발생 시 사용자에게 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openDeviceNotificationSettings() async {
    final text = _SettingText(_language);
    try {
      await widget.onDeviceNotificationSettingsRequested?.call();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.deviceNotificationSettingsFailed)),
      );
    }
  }

  // 함수이름: _selectReadingSpeed
  // 함수역할: 재생 중인 미리보기를 중지한 뒤 새 읽기 속도를 선택한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _selectReadingSpeed(String value) async {
    await _stopVoicePreview();
    if (!mounted) {
      return;
    }
    // 함수이름: _selectReadingSpeed.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_readingSpeed = value`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _readingSpeed = value);
  }

  // 함수이름: _toggleVoicePreview
  // 함수역할: 현재 설정된 언어와 읽기 속도로 예시 문장을 재생하거나 중지한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _toggleVoicePreview() async {
    if (_isPreviewSpeaking) {
      await _stopVoicePreview();
      return;
    }

    final requestId = ++_voicePreviewRequestId;
    final text = _SettingText(_language);
    final previewSetting = UserSetting(
      fontSize: UserSetting.fontSizeFromOption(_fontSize),
      readingSpeed: UserSetting.readingSpeedFromOption(_readingSpeed),
      language: _language,
    );
    // 함수이름: _toggleVoicePreview.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isPreviewSpeaking = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isPreviewSpeaking = true);

    try {
      final speaker = widget.previewSpeaker ?? _ownedTtsService!.speak;
      await speaker(
        text.previewSentence,
        previewSetting,
        // 함수이름: _toggleVoicePreview.onComplete callback
        // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에서 캡처된 작업 `_finishVoicePreview(requestId)`을 실행한다.
        // 매개변수:
        // - 없음.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onComplete: () => _finishVoicePreview(requestId),
      );
    } catch (_) {
      if (!mounted || requestId != _voicePreviewRequestId) {
        return;
      }
      // 함수이름: _toggleVoicePreview.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isPreviewSpeaking = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isPreviewSpeaking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.previewFailed)));
    }
  }

  // 함수이름: _stopVoicePreview
  // 함수역할: 미리보기 음성을 중지하고 버튼 상태를 재생 가능 상태로 되돌린다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _stopVoicePreview() async {
    // 사용자가 중지를 누르면 진행 중인 재생 요청을 먼저 무효화해 취소를 오류와 구분한다.
    _voicePreviewRequestId += 1;
    if (mounted && _isPreviewSpeaking) {
      // 함수이름: _stopVoicePreview.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isPreviewSpeaking = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isPreviewSpeaking = false);
    }

    final stopper = widget.previewStopper;
    try {
      if (stopper != null) {
        await stopper();
      } else {
        await _ownedTtsService?.stop();
      }
    } catch (_) {
      // 사용자가 직접 중지한 경우 플랫폼의 취소 응답은 재생 실패로 안내하지 않는다.
    }
  }

  // 함수이름: _finishVoicePreview
  // 함수역할: TTS 엔진이 재생 완료를 알리면 미리보기 버튼 상태를 복구한다.
  // 매개변수:
  // - requestId (int): 오래된 비동기 결과를 무효화하는 요청 세대.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _finishVoicePreview(int requestId) {
    if (!mounted ||
        requestId != _voicePreviewRequestId ||
        !_isPreviewSpeaking) {
      return;
    }
    // 함수이름: _finishVoicePreview.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isPreviewSpeaking = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isPreviewSpeaking = false);
  }

  // 함수이름: _handleSaveRequested
  // 함수역할: 설정 저장 요청을 한 번만 실행하고 실패 시 버튼 상태를 복구한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _handleSaveRequested() async {
    if (_isSaving) {
      return;
    }

    // 함수이름: _handleSaveRequested.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isSaving = true);
    final text = _SettingText(_language);
    try {
      final extendedSaver = widget.onExtendedSettingSaveRequested;
      final saveResult = extendedSaver != null
          ? await extendedSaver(_draftSetting)
          : await widget.onSettingSaveRequested(
              fontSizeOption: _fontSize,
              readingSpeedOption: _readingSpeed,
              language: _language,
            );
      await widget.onMultiPillIdentificationLabSettingSaveRequested?.call(
        _multiPillIdentificationLabEnabled,
      );
      if (!mounted) {
        return;
      }

      // 함수이름: _handleSaveRequested.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saveResult.synchronizedWithServer
                ? text.saved
                : text.savedOnDeviceOnly,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      // 함수이름: _handleSaveRequested.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.saveFailed)));
    }
  }

  // Function Name: _handleSignOutRequested
  // Description: Blocks overlapping sign-out/deletion, confirms permanent guest-data loss, then signs out and returns to the root or reports the failure.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _handleSignOutRequested() async {
    if (_isSaving) {
      return;
    }

    final text = _SettingText(_language);
    if (widget.authenticationControl.isAnonymous) {
      final confirmed = await showDialog<bool>(
        context: context,
        // Function Name: _handleSignOutRequested.builder callback
        // Description: Composes accessibility, default medication times, and account security settings with the current parent constraints for the active layout.
        // Parameters:
        // - dialogContext (BuildContext): Dialog or sheet context for closing the route and reading theme data.
        // Returns: Widget subtree for the described layout or fallback.
        builder: (dialogContext) => AlertDialog(
          title: Text(text.guestSignOutTitle),
          content: Text(text.guestSignOutMessage),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: MedBuddyColors.textStrong,
              ),
              // 함수이름: _handleSignOutRequested.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext, false)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(text.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.danger,
              ),
              // 함수이름: _handleSignOutRequested.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext, true)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(text.delete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    // 함수이름: _handleSignOutRequested.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isSaving = true);
    try {
      await widget.onSignOutRequested?.call();
      if (!mounted) {
        return;
      }
      // Function Name: _handleSignOutRequested.popUntil callback
      // Description: Supplies `route.isFirst` from the captured state of accessibility, default medication times, and account security settings.
      // Parameters:
      // - route (inferred by callback contract): Navigation route checked for reaching the root.
      // Returns: The value of `route.isFirst`.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) {
        return;
      }
      // 함수이름: _handleSignOutRequested.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.signOutFailed)));
    }
  }

  // Function Name: _showMfaEnrollment
  // Description: Opens SMS multi-factor enrollment with outside-tap dismissal disabled.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _showMfaEnrollment() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Function Name: _showMfaEnrollment.builder callback
      // Description: Composes accessibility, default medication times, and account security settings with the current parent constraints for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) =>
          _MfaEnrollmentDialog(control: widget.authenticationControl),
    );
  }

  // Function Name: _confirmAccountDeletion
  // Description: Requests account deletion after explicit confirmation, then returns to the root or displays the error.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _confirmAccountDeletion() async {
    final text = _SettingText(_language);
    final confirmed = await showDialog<bool>(
      context: context,
      // 함수이름: _confirmAccountDeletion.builder callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (dialogContext) => AlertDialog(
        title: Text(text.deleteAccount),
        content: Text(text.deleteAccountMessage),
        actions: [
          TextButton(
            // 함수이름: _confirmAccountDeletion.onPressed callback
            // 함수역할: `Navigator.pop(dialogContext, false)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(text.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MedBuddyColors.danger,
            ),
            // 함수이름: _confirmAccountDeletion.onPressed callback
            // 함수역할: `Navigator.pop(dialogContext, true)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(text.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    // 함수이름: _confirmAccountDeletion.setState callback
    // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _isSaving = true);
    try {
      await widget.onDeleteAccountRequested?.call();
      if (!mounted) {
        return;
      }
      // Function Name: _confirmAccountDeletion.popUntil callback
      // Description: Supplies `route.isFirst` from the captured state of accessibility, default medication times, and account security settings.
      // Parameters:
      // - route (inferred by callback contract): Navigation route checked for reaching the root.
      // Returns: The value of `route.isFirst`.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }
      // 함수이름: _confirmAccountDeletion.setState callback
      // 함수역할: 접근성·기본 복약 시각·계정 보안 설정의 입력·요청 상태를 `_isSaving = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : text.deleteAccountFailed,
          ),
        ),
      );
    }
  }
}

// 클래스명: _AccountPresentation
// 역할: 사용자 계정 종류에 맞춘 표시 이름과 설명을 담당한다.
// 주요 책임:
// - 사용자 계정 종류에 맞춘 표시 이름과 설명 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - greeting (String): 계정 이름을 반영한 환영 문구.
// - detail (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
class _AccountPresentation {
  final String greeting;
  final String detail;

  // 함수이름: _AccountPresentation
  // 함수역할: 사용자 계정 종류에 맞춘 표시 이름과 설명 관련 값을 _AccountPresentation 인스턴스에 담는다.
  // 매개변수:
  // - greeting (String): 계정 이름을 반영한 환영 문구.
  // - detail (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // 반환값: 입력 설정이 반영된 _AccountPresentation 인스턴스.
  const _AccountPresentation({required this.greeting, required this.detail});
}

// 클래스명: _SettingsOverview
// 역할: 계정 환영 영역과 설정 분류 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 계정 환영 영역과 설정 분류 목록 위젯을 구성한다.
// 속성:
// - accountPresentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
// - medicationAndNotificationSummary (String): 설정 분류에 표시할 현재 선택값 요약.
// - displayAndVoiceSummary (String): 설정 분류에 표시할 현재 선택값 요약.
// - laboratorySummary (String): 설정 분류에 표시할 현재 선택값 요약.
class _SettingsOverview extends StatelessWidget {
  final _SettingText text;
  final _AccountPresentation accountPresentation;
  final String medicationAndNotificationSummary;
  final String displayAndVoiceSummary;
  final String laboratorySummary;
  final ValueChanged<_SettingSection> onSectionSelected;

  // 함수이름: _SettingsOverview
  // 함수역할: 계정 환영 영역과 설정 분류 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - accountPresentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
  // - medicationAndNotificationSummary (String): 설정 분류에 표시할 현재 선택값 요약.
  // - displayAndVoiceSummary (String): 설정 분류에 표시할 현재 선택값 요약.
  // - laboratorySummary (String): 설정 분류에 표시할 현재 선택값 요약.
  // - onSectionSelected (ValueChanged<_SettingSection>): 선택한 설정 분류를 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingsOverview 인스턴스.
  const _SettingsOverview({
    required this.text,
    required this.accountPresentation,
    required this.medicationAndNotificationSummary,
    required this.displayAndVoiceSummary,
    required this.laboratorySummary,
    required this.onSectionSelected,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 계정 환영 영역과 설정 분류 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 계정 환영 영역과 설정 분류 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.settingsTitle),
        const SizedBox(height: 24),
        _AccountWelcomePanel(presentation: accountPresentation),
        const SizedBox(height: 28),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsMedicationAndNotificationsMenu'),
          icon: Icons.notifications_active_outlined,
          title: text.medicationAndNotificationsTitle,
          summary: medicationAndNotificationSummary,
          // 함수이름: build.onTap callback
          // 함수역할: 계정 환영 영역과 설정 분류 목록에서 캡처된 작업 `onSectionSelected(_SettingSection.medicationAndNotifications)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () =>
              onSectionSelected(_SettingSection.medicationAndNotifications),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsDisplayAndVoiceMenu'),
          icon: Icons.text_fields_rounded,
          title: text.displayAndVoiceTitle,
          summary: displayAndVoiceSummary,
          // 함수이름: build.onTap callback
          // 함수역할: 계정 환영 영역과 설정 분류 목록에서 캡처된 작업 `onSectionSelected(_SettingSection.displayAndVoice)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () => onSectionSelected(_SettingSection.displayAndVoice),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsLaboratoryMenu'),
          icon: Icons.science_outlined,
          title: text.laboratoryTitle,
          summary: laboratorySummary,
          // 함수이름: build.onTap callback
          // 함수역할: 계정 환영 영역과 설정 분류 목록에서 캡처된 작업 `onSectionSelected(_SettingSection.laboratory)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () => onSectionSelected(_SettingSection.laboratory),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsAccountMenu'),
          icon: Icons.manage_accounts_outlined,
          title: text.accountTitle,
          summary: text.accountMenuSummary,
          // 함수이름: build.onTap callback
          // 함수역할: 계정 환영 영역과 설정 분류 목록에서 캡처된 작업 `onSectionSelected(_SettingSection.account)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () => onSectionSelected(_SettingSection.account),
        ),
        const SizedBox(height: 24),
        const Center(child: AppVersionLabel()),
      ],
    );
  }
}

// 클래스명: _AccountWelcomePanel
// 역할: 계정 이름·로그인 상태·관련 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 계정 이름·로그인 상태·관련 명령 위젯을 구성한다.
// 속성:
// - presentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
// - compact (bool): 공간을 줄인 카드·상단 배치를 사용할지 여부.
class _AccountWelcomePanel extends StatelessWidget {
  final _AccountPresentation presentation;
  final bool compact;

  // 함수이름: _AccountWelcomePanel
  // 함수역할: 계정 이름·로그인 상태·관련 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - presentation (_AccountPresentation): 현재 계정 또는 변화 유형의 표시 모델.
  // - compact (bool): 공간을 줄인 카드·상단 배치를 사용할지 여부.
  // 반환값: 입력 설정이 반영된 _AccountWelcomePanel 인스턴스.
  const _AccountWelcomePanel({
    required this.presentation,
    this.compact = false,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 계정 이름·로그인 상태·관련 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 계정 이름·로그인 상태·관련 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 20),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: MedBuddyRadii.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MedBuddyRadii.card,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_outline_rounded,
              color: MedBuddyColors.primary,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.greeting,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 19,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  presentation.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _SettingsMenuTile
// 역할: 설정 분류의 아이콘·설명·이동 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 분류의 아이콘·설명·이동 명령 위젯을 구성한다.
// 속성:
// - tileKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - summary (String): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
class _SettingsMenuTile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  // 함수이름: _SettingsMenuTile
  // 함수역할: 설정 분류의 아이콘·설명·이동 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - tileKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - summary (String): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingsMenuTile 인스턴스.
  const _SettingsMenuTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 분류의 아이콘·설명·이동 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 분류의 아이콘·설명·이동 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title, $summary',
      button: true,
      child: ExcludeSemantics(
        child: Material(
          key: tileKey,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: MedBuddyRadii.card,
            side: const BorderSide(color: MedBuddyColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  Icon(icon, color: MedBuddyColors.primary, size: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 19,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          summary,
                          style: const TextStyle(
                            color: MedBuddyColors.textMuted,
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: MedBuddyColors.textLight,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Class Name: _MfaSettingsPanel
// Role: Represents SMS multi-factor enrollment state and security actions.
// Responsibilities:
// - Composes SMS multi-factor enrollment state and security actions using the display values and actions supplied by its parent.
// Attributes:
// - enabled (bool): Whether the choice, action, or feature is enabled.
// - available (bool): Whether the choice, action, or feature is enabled.
// - onEnrollRequested (VoidCallback): Callback starting SMS multi-factor enrollment.
class _MfaSettingsPanel extends StatelessWidget {
  final bool enabled;
  final bool available;
  final VoidCallback onEnrollRequested;

  // Function Name: _MfaSettingsPanel
  // Description: Initializes SMS multi-factor enrollment state and security actions with the supplied configuration.
  // Parameters:
  // - enabled (bool): Whether the choice, action, or feature is enabled.
  // - available (bool): Whether the choice, action, or feature is enabled.
  // - onEnrollRequested (VoidCallback): Callback starting SMS multi-factor enrollment.
  // Returns: Initialized _MfaSettingsPanel instance.
  const _MfaSettingsPanel({
    required this.enabled,
    required this.available,
    required this.onEnrollRequested,
  });

  // Function Name: build
  // Description: Renders SMS multi-factor enrollment state and security actions from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for SMS multi-factor enrollment state and security actions.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SMS two-step verification',
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            enabled
                ? 'An SMS second factor is enrolled.'
                : available
                ? 'Protect this account with a verified phone number.'
                : 'Available for verified email or Google accounts.',
            style: const TextStyle(color: MedBuddyColors.textMuted),
          ),
          if (available && !enabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onEnrollRequested,
              icon: const Icon(Icons.security_outlined),
              label: const Text('Enable SMS MFA'),
            ),
          ],
        ],
      ),
    );
  }
}

// Class Name: _MfaEnrollmentDialog
// Role: Represents phone-number entry and SMS multi-factor enrollment.
// Responsibilities:
// - Holds the configuration consumed by the State responsible for phone-number entry and SMS multi-factor enrollment.
// Attributes:
// - control (AuthenticationControl): Controller handling this screen's queries and update requests.
class _MfaEnrollmentDialog extends StatefulWidget {
  final AuthenticationControl control;

  // Function Name: _MfaEnrollmentDialog
  // Description: Initializes phone-number entry and SMS multi-factor enrollment with the supplied configuration.
  // Parameters:
  // - control (AuthenticationControl): Controller handling this screen's queries and update requests.
  // Returns: Initialized _MfaEnrollmentDialog instance.
  const _MfaEnrollmentDialog({required this.control});

  // Function Name: createState
  // Description: Creates the state object that coordinates phone-number entry and SMS multi-factor enrollment.
  // Parameters:
  // - None.
  // Returns: A new _MfaEnrollmentDialogState instance.
  @override
  State<_MfaEnrollmentDialog> createState() => _MfaEnrollmentDialogState();
}

// Class Name: _MfaEnrollmentDialogState
// Role: Manages state for phone-number entry and SMS multi-factor enrollment.
// Responsibilities:
// - Coordinates updates and interactions for phone-number entry and SMS multi-factor enrollment.
class _MfaEnrollmentDialogState extends State<_MfaEnrollmentDialog> {
  final _phoneController = TextEditingController(text: '+82');
  final _codeController = TextEditingController();

  // Function Name: dispose
  // Description: Releases _phoneController, _codeController and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // Function Name: build
  // Description: Renders phone-number entry and SMS multi-factor enrollment from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for phone-number entry and SMS multi-factor enrollment.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.control,
      // Function Name: build.builder callback
      // Description: Composes phone-number entry and SMS multi-factor enrollment with Text for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context, _) {
        final awaitingCode =
            widget.control.smsChallengePurpose ==
            SmsChallengePurpose.mfaEnrollment;
        return AlertDialog(
          title: Text(awaitingCode ? 'Verify phone' : 'Enable SMS MFA'),
          content: TextField(
            controller: awaitingCode ? _codeController : _phoneController,
            autofocus: true,
            keyboardType: TextInputType.phone,
            maxLength: awaitingCode ? 6 : null,
            decoration: InputDecoration(
              labelText: awaitingCode
                  ? 'Six-digit SMS code'
                  : 'International phone number',
              hintText: awaitingCode ? null : '+821012345678',
            ),
          ),
          actions: [
            TextButton(
              onPressed: widget.control.isBusy
                  ? null
                  // Function Name: build.onPressed callback
                  // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
                  // Parameters:
                  // - None.
                  // Returns: No callback payload; any selection is delivered through the route result.
                  : () {
                      widget.control.cancelSmsChallenge();
                      Navigator.pop(context);
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: widget.control.isBusy
                  ? null
                  // Function Name: build.onPressed callback
                  // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
                  // Parameters:
                  // - None.
                  // Returns: No callback payload; any selection is delivered through the route result.
                  : () async {
                      if (!awaitingCode) {
                        await widget.control.startSmsMfaEnrollment(
                          _phoneController.text,
                        );
                        return;
                      }
                      await widget.control.submitSmsCode(_codeController.text);
                      if (context.mounted &&
                          !widget.control.smsCodeRequired &&
                          widget.control.errorMessage == null) {
                        Navigator.pop(context);
                      }
                    },
              child: Text(awaitingCode ? 'Verify' : 'Send code'),
            ),
          ],
        );
      },
    );
  }
}

// 클래스명: _SettingsBackButton
// 역할: 설정 하위 화면에서 이전 단계로 이동을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 하위 화면에서 이전 단계로 이동 위젯을 구성한다.
// 속성:
// - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _SettingsBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  // 함수이름: _SettingsBackButton
  // 함수역할: 설정 하위 화면에서 이전 단계로 이동에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingsBackButton 인스턴스.
  const _SettingsBackButton({required this.tooltip, required this.onTap});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 하위 화면에서 이전 단계로 이동 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 하위 화면에서 이전 단계로 이동에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: ExcludeSemantics(
        child: IconButton(
          key: const ValueKey('settingsBackButton'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          tooltip: tooltip,
          onPressed: onTap,
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF4A5565),
            size: 31,
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SettingSaveFooter
// 역할: 설정 변경사항 저장 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 변경사항 저장 명령 위젯을 구성한다.
// 속성:
// - isSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
// - onSaveRequested (Future<void> Function()): 검증한 약품과 복약 정보를 저장할 콜백.
class _SettingSaveFooter extends StatelessWidget {
  final _SettingText text;
  final bool isSaving;
  final Future<void> Function() onSaveRequested;

  // 함수이름: _SettingSaveFooter
  // 함수역할: 설정 변경사항 저장 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - isSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - onSaveRequested (Future<void> Function()): 검증한 약품과 복약 정보를 저장할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingSaveFooter 인스턴스.
  const _SettingSaveFooter({
    required this.text,
    required this.isSaving,
    required this.onSaveRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 변경사항 저장 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 변경사항 저장 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 20),
      decoration: const BoxDecoration(
        color: MedBuddyColors.pageBackground,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: Semantics(
          label: isSaving ? text.saving : text.save,
          button: true,
          enabled: !isSaving,
          child: ExcludeSemantics(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MedBuddyColors.primary.withAlpha(150),
                shape: RoundedRectangleBorder(borderRadius: MedBuddyRadii.card),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              onPressed: isSaving ? null : onSaveRequested,
              child: Text(isSaving ? text.saving : text.save),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SettingTitle
// 역할: 설정 하위 화면 제목을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 하위 화면 제목 위젯을 구성한다.
class _SettingTitle extends StatelessWidget {
  final String text;

  // 함수이름: _SettingTitle
  // 함수역할: 설정 하위 화면 제목에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (String): 해당 라벨 또는 정보 행에 표시할 문자열.
  // 반환값: 입력 설정이 반영된 _SettingTitle 인스턴스.
  const _SettingTitle(this.text);

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 하위 화면 제목 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 하위 화면 제목에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: 0,
      ),
    );
  }
}

// 클래스명: _SettingFieldTitle
// 역할: 설정 입력 항목의 제목을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 입력 항목의 제목 위젯을 구성한다.
class _SettingFieldTitle extends StatelessWidget {
  final String text;

  // 함수이름: _SettingFieldTitle
  // 함수역할: 설정 입력 항목의 제목에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (String): 해당 라벨 또는 정보 행에 표시할 문자열.
  // 반환값: 입력 설정이 반영된 _SettingFieldTitle 인스턴스.
  const _SettingFieldTitle(this.text);

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 입력 항목의 제목 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 입력 항목의 제목에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

// 클래스명: _ExperimentalFeatureToggle
// 역할: 실험 기능 설명과 사용 여부 선택을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 실험 기능 설명과 사용 여부 선택 위젯을 구성한다.
// 속성:
// - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
class _ExperimentalFeatureToggle extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  // 함수이름: _ExperimentalFeatureToggle
  // 함수역할: 실험 기능 설명과 사용 여부 선택에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onChanged (ValueChanged<bool>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _ExperimentalFeatureToggle 인스턴스.
  const _ExperimentalFeatureToggle({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 실험 기능 설명과 사용 여부 선택 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 실험 기능 설명과 사용 여부 선택에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: switchKey,
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: MedBuddyColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            description,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SettingToggle
// 역할: 이진 설정의 라벨·설명·현재 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 이진 설정의 라벨·설명·현재 값 위젯을 구성한다.
// 속성:
// - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
class _SettingToggle extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  // 함수이름: _SettingToggle
  // 함수역할: 이진 설정의 라벨·설명·현재 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - switchKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onChanged (ValueChanged<bool>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingToggle 인스턴스.
  const _SettingToggle({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 이진 설정의 라벨·설명·현재 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 이진 설정의 라벨·설명·현재 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: switchKey,
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: MedBuddyColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        title: Text(
          title,
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            description,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SettingsActionTile
// 역할: 설정 화면의 별도 작업 실행 행을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 화면의 별도 작업 실행 행 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  // 함수이름: _SettingsActionTile
  // 함수역할: 설정 화면의 별도 작업 실행 행에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _SettingsActionTile 인스턴스.
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정 화면의 별도 작업 실행 행 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 화면의 별도 작업 실행 행에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MedBuddyColors.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _DefaultMedicationTimePanel
// 역할: 아침·점심·저녁·취침 전 기본 복약 시각을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 아침·점심·저녁·취침 전 기본 복약 시각 위젯을 구성한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - morningTime (String): 해당 복약 시간대의 기본 시:분 값.
// - lunchTime (String): 해당 복약 시간대의 기본 시:분 값.
// - eveningTime (String): 해당 복약 시간대의 기본 시:분 값.
class _DefaultMedicationTimePanel extends StatelessWidget {
  final _SettingText text;
  final UserSetting userSetting;
  final String morningTime;
  final String lunchTime;
  final String eveningTime;
  final String bedtime;
  final ValueChanged<String> onTimeRequested;

  // 함수이름: _DefaultMedicationTimePanel
  // 함수역할: 아침·점심·저녁·취침 전 기본 복약 시각에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - morningTime (String): 해당 복약 시간대의 기본 시:분 값.
  // - lunchTime (String): 해당 복약 시간대의 기본 시:분 값.
  // - eveningTime (String): 해당 복약 시간대의 기본 시:분 값.
  // - bedtime (String): 해당 복약 시간대의 기본 시:분 값.
  // - onTimeRequested (ValueChanged<String>): 수정할 복약 시간대의 시간 선택을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _DefaultMedicationTimePanel 인스턴스.
  const _DefaultMedicationTimePanel({
    required this.text,
    required this.userSetting,
    required this.morningTime,
    required this.lunchTime,
    required this.eveningTime,
    required this.bedtime,
    required this.onTimeRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 아침·점심·저녁·취침 전 기본 복약 시각 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 아침·점심·저녁·취침 전 기본 복약 시각에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final entries = [
      ('morning', text.morning, morningTime, Icons.wb_sunny_outlined),
      ('lunch', text.lunch, lunchTime, Icons.lunch_dining_outlined),
      ('evening', text.evening, eveningTime, Icons.wb_twilight_outlined),
      ('bedtime', text.bedtime, bedtime, Icons.bedtime_outlined),
    ];
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int index = 0; index < entries.length; index++) ...[
            ListTile(
              // 함수이름: build.onTap callback
              // 함수역할: 아침·점심·저녁·취침 전 기본 복약 시각에서 캡처된 작업 `onTimeRequested(entries[index].$1)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onTap: () => onTimeRequested(entries[index].$1),
              leading: Icon(entries[index].$4, color: MedBuddyColors.primary),
              title: Text(
                entries[index].$2,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Text(
                userSetting.formatTimeValue(entries[index].$3),
                style: const TextStyle(
                  color: MedBuddyColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (index != entries.length - 1)
              const Divider(height: 1, color: MedBuddyColors.divider),
          ],
        ],
      ),
    );
  }
}

// 클래스명: _StackedOptionList
// 역할: 설정값을 세로로 비교하는 선택 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정값을 세로로 비교하는 선택 목록 위젯을 구성한다.
// 속성:
// - options (List<_SettingOption>): 선택 가능한 설정 값과 표시 정보.
// - selectedValue (String): 현재 선택한 시·분 또는 선택지 값.
// - onSelected (ValueChanged<String>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _StackedOptionList extends StatelessWidget {
  final List<_SettingOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  // 함수이름: _StackedOptionList
  // 함수역할: 설정값을 세로로 비교하는 선택 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - options (List<_SettingOption>): 선택 가능한 설정 값과 표시 정보.
  // - selectedValue (String): 현재 선택한 시·분 또는 선택지 값.
  // - onSelected (ValueChanged<String>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _StackedOptionList 인스턴스.
  const _StackedOptionList({
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 설정값을 세로로 비교하는 선택 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정값을 세로로 비교하는 선택 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int index = 0; index < options.length; index++) ...[
            Semantics(
              selected: options[index].value == selectedValue,
              button: true,
              child: ListTile(
                // Function Name: build.onTap callback
                // Description: Connects a vertical list of mutually selectable setting values to the captured operation `onSelected(options[index].value)`.
                // Parameters:
                // - None.
                // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                onTap: () => onSelected(options[index].value),
                leading: Icon(
                  options[index].value == selectedValue
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: options[index].value == selectedValue
                      ? MedBuddyColors.primary
                      : MedBuddyColors.textLight,
                ),
                title: Text(
                  options[index].label,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (index != options.length - 1)
              const Divider(height: 1, color: MedBuddyColors.divider),
          ],
        ],
      ),
    );
  }
}

// Class Name: _OptionRow
// Role: Represents a setting option and its selected indicator.
// Responsibilities:
// - Composes a setting option and its selected indicator using the display values and actions supplied by its parent.
// Attributes:
// - options (List<_SettingOption>): Selectable setting values and their presentation data.
// - selectedValue (String): Currently selected hour, minute, or option value.
// - contentScale (double): Content text scale reflecting user accessibility settings.
// - onSelected (ValueChanged<String>): Callback reporting the changed value or selection state to the owning screen.
class _OptionRow extends StatelessWidget {
  final List<_SettingOption> options;
  final String selectedValue;
  final double contentScale;
  final ValueChanged<String> onSelected;

  // 함수이름: _OptionRow
  // 함수역할: 설정 선택지와 현재 선택 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - options (List<_SettingOption>): 선택 가능한 설정 값과 표시 정보.
  // - selectedValue (String): 현재 선택한 시·분 또는 선택지 값.
  // - contentScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onSelected (ValueChanged<String>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _OptionRow 인스턴스.
  const _OptionRow({
    required this.options,
    required this.selectedValue,
    required this.contentScale,
    required this.onSelected,
  });

  // Function Name: build
  // Description: Renders a setting option and its selected indicator from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a setting option and its selected indicator.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int index = 0; index < options.length; index++) ...[
          Expanded(
            child: _SegmentButton(
              option: options[index],
              selected: options[index].value == selectedValue,
              contentScale: contentScale,
              // Function Name: build.onTap callback
              // Description: Connects a setting option and its selected indicator to the captured operation `onSelected(options[index].value)`.
              // Parameters:
              // - None.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              onTap: () => onSelected(options[index].value),
            ),
          ),
          if (index != options.length - 1) const SizedBox(width: 11),
        ],
      ],
    );
  }
}

// Class Name: _SegmentButton
// Role: Represents one selectable segment for a setting value.
// Responsibilities:
// - Composes one selectable segment for a setting value using the display values and actions supplied by its parent.
// Attributes:
// - option (_SettingOption): Selectable setting values and their presentation data.
// - selected (bool): Whether the item belongs to the current selection.
// - contentScale (double): Content text scale reflecting user accessibility settings.
// - onTap (VoidCallback?): Callback executing the item's documented primary action.
class _SegmentButton extends StatelessWidget {
  final _SettingOption option;
  final bool selected;
  final double contentScale;
  final VoidCallback? onTap;

  // 함수이름: _SegmentButton
  // 함수역할: 설정값 분할 선택 버튼에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - option (_SettingOption): 선택 가능한 설정 값과 표시 정보.
  // - selected (bool): 현재 선택 집합에 포함되는지 여부.
  // - contentScale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _SegmentButton 인스턴스.
  const _SegmentButton({
    required this.option,
    required this.selected,
    required this.contentScale,
    required this.onTap,
  });

  // Function Name: build
  // Description: Renders one selectable segment for a setting value from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for one selectable segment for a setting value.
  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected ? MedBuddyColors.primary : Colors.white;
    final foregroundColor = selected ? Colors.white : MedBuddyColors.textStrong;

    return Semantics(
      label: option.label,
      button: true,
      enabled: true,
      selected: selected,
      child: ExcludeSemantics(
        child: Material(
          color: backgroundColor,
          borderRadius: MedBuddyRadii.card,
          elevation: selected ? 7 : 0,
          shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
          child: InkWell(
            borderRadius: MedBuddyRadii.card,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 77),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: MedBuddyRadii.card,
                border: Border.all(
                  color: MedBuddyColors.primary,
                  width: selected ? 0 : 2.7,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: option.labelFontSize == null
                        ? null
                        : TextScaler.noScaling,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: option.labelFontSize ?? 16 * contentScale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _PreviewPanel
// 역할: 현재 글씨 크기·언어 설정의 미리보기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 현재 글씨 크기·언어 설정의 미리보기 위젯을 구성한다.
// 속성:
// - fontSize (String): 기준 글씨 크기 또는 선택한 크기 옵션.
// - readingSpeed (String): 읽어주기에 사용할 음성 속도 옵션.
// - isSpeaking (bool): 읽어주기가 현재 재생 중인지 여부.
// - onVoicePreviewRequested (VoidCallback): 현재 언어·속도로 음성 미리보기를 시작·중지할 콜백.
class _PreviewPanel extends StatelessWidget {
  final _SettingText text;
  final String fontSize;
  final String readingSpeed;
  final bool isSpeaking;
  final VoidCallback onVoicePreviewRequested;

  // 함수이름: _PreviewPanel
  // 함수역할: 현재 글씨 크기·언어 설정의 미리보기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SettingText): 해당 화면 구역의 언어별 표시 문구.
  // - fontSize (String): 기준 글씨 크기 또는 선택한 크기 옵션.
  // - readingSpeed (String): 읽어주기에 사용할 음성 속도 옵션.
  // - isSpeaking (bool): 읽어주기가 현재 재생 중인지 여부.
  // - onVoicePreviewRequested (VoidCallback): 현재 언어·속도로 음성 미리보기를 시작·중지할 콜백.
  // 반환값: 입력 설정이 반영된 _PreviewPanel 인스턴스.
  const _PreviewPanel({
    required this.text,
    required this.fontSize,
    required this.readingSpeed,
    required this.isSpeaking,
    required this.onVoicePreviewRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 현재 글씨 크기·언어 설정의 미리보기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 현재 글씨 크기·언어 설정의 미리보기에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final speedLabel = switch (readingSpeed) {
      'slow' => text.slowLabel,
      'fast' => text.fastLabel,
      _ => text.normalLabel,
    };
    final textSize = switch (fontSize) {
      'small' => 13.0,
      'large' => 20.0,
      _ => 15.0,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.preview,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MedBuddyRadii.card,
            ),
            child: Text(
              text.previewSentence,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: textSize,
                height: 1.55,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${text.readingSpeedLabel}: $speedLabel',
              style: const TextStyle(
                color: MedBuddyColors.textLight,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onVoicePreviewRequested,
              icon: Icon(
                isSpeaking ? Icons.stop_rounded : Icons.volume_up_outlined,
              ),
              label: Text(isSpeaking ? text.stopPreview : text.listenPreview),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _SettingOption
// 역할: 설정 선택지의 저장 값과 표시 문구를 담당한다.
// 주요 책임:
// - 설정 선택지의 저장 값과 표시 문구 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - labelFontSize (double?): 기준 글씨 크기 또는 선택한 크기 옵션.
class _SettingOption {
  final String value;
  final String label;

  final double? labelFontSize;

  // 함수이름: _SettingOption
  // 함수역할: 설정 선택지의 저장 값과 표시 문구 관련 값을 _SettingOption 인스턴스에 담는다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - labelFontSize (double?): 기준 글씨 크기 또는 선택한 크기 옵션.
  // 반환값: 입력 설정이 반영된 _SettingOption 인스턴스.
  const _SettingOption({
    required this.value,
    required this.label,

    this.labelFontSize,
  });
}

// 클래스명: _SettingText
// 역할: 접근성·알림·실험 기능·계정 보안 설정에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 접근성·알림·실험 기능·계정 보안 설정에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _SettingText {
  final String language;

  // 함수이름: _SettingText
  // 함수역할: 접근성·알림·실험 기능·계정 보안 설정에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _SettingText 인스턴스.
  const _SettingText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: settingsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "환경설정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get settingsTitle => isEnglish ? 'Settings' : '환경설정';
  // 함수이름: medicationAndNotificationsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 및 알림" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationAndNotificationsTitle =>
      isEnglish ? 'Medication & Notifications' : '복약 및 알림';
  // 함수이름: displayAndVoiceTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "화면 및 음성" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get displayAndVoiceTitle => isEnglish ? 'Display & Voice' : '화면 및 음성';
  // 함수이름: fontSizeTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "글씨크기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get fontSizeTitle => isEnglish ? 'Text Size' : '글씨크기';
  // 함수이름: readingSpeedTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "읽기속도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get readingSpeedTitle => isEnglish ? 'Reading Speed' : '읽기속도';
  // 함수이름: languageTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "Language" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get languageTitle => isEnglish ? 'Language' : '언어';
  // 함수이름: laboratoryTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "실험실" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get laboratoryTitle => isEnglish ? 'Labs' : '실험실';
  // 함수이름: accountTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "Account" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get accountTitle => isEnglish ? 'Account' : '계정';
  // 함수이름: defaultUserName
  // 함수역할: 현재 언어와 입력값에 맞춰 "사용자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get defaultUserName => isEnglish ? 'MedBuddy User' : '사용자';
  // 함수이름: welcome
  // 함수역할: 현재 언어와 입력값에 맞춰 "$name님, 안녕하세요" 문구를 제공한다.
  // 매개변수:
  // - name (String): 사용자에게 표시할 약품 또는 계정 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String welcome(String name) => isEnglish ? 'Welcome, $name' : '$name님, 안녕하세요';
  // 함수이름: guestAccount
  // 함수역할: 현재 언어와 입력값에 맞춰 "게스트 계정으로 사용 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get guestAccount =>
      isEnglish ? 'Using a guest account' : '게스트 계정으로 사용 중';
  // 함수이름: localDemoAccount
  // 함수역할: 현재 언어와 입력값에 맞춰 "로컬 데모 계정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get localDemoAccount => isEnglish ? 'Local demo account' : '로컬 데모 계정';
  // 함수이름: signedInAccount
  // 함수역할: 현재 언어와 입력값에 맞춰 "MedBuddy 계정으로 로그인됨" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get signedInAccount =>
      isEnglish ? 'Signed in to MedBuddy' : 'MedBuddy 계정으로 로그인됨';
  // 함수이름: accountMenuSummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "로그인, 보안 및 계정 데이터 관리" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get accountMenuSummary =>
      isEnglish ? 'Sign-in, security, and account data' : '로그인, 보안 및 계정 데이터 관리';
  // 함수이름: noAccountActions
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 실행 모드에서는 추가로 변경할 계정 설정이 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noAccountActions => isEnglish
      ? 'No additional account actions are available in this mode.'
      : '현재 실행 모드에서는 추가로 변경할 계정 설정이 없습니다.';
  // 함수이름: multiPillIdentificationLabTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "다중 알약 일괄 식별" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get multiPillIdentificationLabTitle =>
      isEnglish ? 'Multi-pill batch identification' : '다중 알약 일괄 식별';
  // 함수이름: multiPillIdentificationLabDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "알약마다 사진을 한 장씩 추가해 여러 식별 결과를 한 번에 검토합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get multiPillIdentificationLabDescription => isEnglish
      ? 'Add one photo per pill and review several identification results together.'
      : '알약마다 사진을 한 장씩 추가해 여러 식별 결과를 한 번에 검토합니다.';
  // 함수이름: medicationNotificationsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "내 복약 알림" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationNotificationsTitle =>
      isEnglish ? 'My medication reminders' : '내 복약 알림';
  // 함수이름: medicationNotificationsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시간에 맞춰 내 휴대폰으로 알림을 받습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationNotificationsDescription => isEnglish
      ? 'Receive reminders for your scheduled medication times.'
      : '복용 시간에 맞춰 내 휴대폰으로 알림을 받습니다.';
  // 함수이름: caregiverNotificationsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "보호자 알림" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caregiverNotificationsTitle =>
      isEnglish ? 'Caregiver updates' : '보호자 알림';
  // 함수이름: caregiverNotificationsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동된 환자의 복약 상태 알림을 받습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caregiverNotificationsDescription => isEnglish
      ? 'Receive medication updates for linked patients.'
      : '연동된 환자의 복약 상태 알림을 받습니다.';
  // 함수이름: chatNotificationsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "채팅 알림" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get chatNotificationsTitle =>
      isEnglish ? 'Chat notifications' : '채팅 알림';
  // 함수이름: chatNotificationsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 대화에 새 메시지가 오면 알림을 받습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get chatNotificationsDescription => isEnglish
      ? 'Receive notifications for new medication conversations.'
      : '복약 대화에 새 메시지가 오면 알림을 받습니다.';
  // 함수이름: deviceNotificationSettingsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "휴대폰 알림 설정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deviceNotificationSettingsTitle =>
      isEnglish ? 'Phone notification settings' : '휴대폰 알림 설정';
  // 함수이름: deviceNotificationSettingsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "알림 권한과 휴대폰 잠금 화면 표시를 확인합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deviceNotificationSettingsDescription => isEnglish
      ? 'Review notification permission and lock-screen behavior.'
      : '알림 권한과 휴대폰 잠금 화면 표시를 확인합니다.';
  // 함수이름: deviceNotificationSettingsFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "휴대폰 알림 설정을 열지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deviceNotificationSettingsFailed => isEnglish
      ? 'Could not open the phone notification settings.'
      : '휴대폰 알림 설정을 열지 못했습니다.';
  // 함수이름: defaultMedicationTimeTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "기본 복약 시간" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get defaultMedicationTimeTitle =>
      isEnglish ? 'Default medication times' : '기본 복약 시간';
  // 함수이름: defaultMedicationTimeDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "새로 등록하는 복약 일정의 처음 시각으로만 사용합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get defaultMedicationTimeDescription => isEnglish
      ? 'Used only as the initial time for newly added medication schedules.'
      : '새로 등록하는 복약 일정의 처음 시각으로만 사용합니다.';
  // 함수이름: detailedScheduleSettingsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "시간대별 세부 설정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get detailedScheduleSettingsTitle =>
      isEnglish ? 'Schedule-specific settings' : '시간대별 세부 설정';
  // 함수이름: detailedScheduleSettingsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘의 복약 일정에서 기존 알림 시각을 따로 조정합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get detailedScheduleSettingsDescription => isEnglish
      ? 'Open today’s medication schedule to adjust existing reminders.'
      : '오늘의 복약 일정에서 기존 알림 시각을 따로 조정합니다.';
  // 함수이름: notificationPrivacyTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "잠금 화면 개인정보" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get notificationPrivacyTitle =>
      isEnglish ? 'Lock-screen privacy' : '잠금 화면 개인정보';
  // 함수이름: notificationPrivacyDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "알림에 약 이름과 채팅 내용을 표시할지 선택합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get notificationPrivacyDescription => isEnglish
      ? 'Choose whether medication names and chat messages appear in notifications.'
      : '알림에 약 이름과 채팅 내용을 표시할지 선택합니다.';
  // 함수이름: notificationPrivacyFull
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름과 메시지 모두 표시" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get notificationPrivacyFull =>
      isEnglish ? 'Show medication names and messages' : '약 이름과 메시지 모두 표시';
  // 함수이름: notificationPrivacyTypeOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "알림 종류만 표시" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get notificationPrivacyTypeOnly =>
      isEnglish ? 'Show notification type only' : '알림 종류만 표시';
  // 함수이름: followDeviceLanguage
  // 함수역할: 현재 언어와 입력값에 맞춰 "기기 설정 따르기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get followDeviceLanguage =>
      isEnglish ? 'Use device language' : '기기 설정 따르기';
  // 함수이름: timeFormatTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "시간 표시" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get timeFormatTitle => isEnglish ? 'Time display' : '시간 표시';
  // 함수이름: twelveHourTime
  // 함수역할: 현재 언어와 입력값에 맞춰 "오전/오후" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get twelveHourTime => isEnglish ? 'AM/PM' : '오전/오후';
  // 함수이름: twentyFourHourTime
  // 함수역할: 현재 언어와 입력값에 맞춰 "24시간제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get twentyFourHourTime => isEnglish ? '24-hour' : '24시간제';
  // 함수이름: morning
  // 함수역할: 현재 언어와 입력값에 맞춰 "Morning" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get morning => isEnglish ? 'Morning' : '아침';
  // 함수이름: lunch
  // 함수역할: 현재 언어와 입력값에 맞춰 "Lunch" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get lunch => isEnglish ? 'Lunch' : '점심';
  // 함수이름: evening
  // 함수역할: 현재 언어와 입력값에 맞춰 "Evening" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get evening => isEnglish ? 'Evening' : '저녁';
  // 함수이름: bedtime
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get bedtime => isEnglish ? 'Bedtime' : '취침 전';
  // 함수이름: defaultTimeLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "$slotTitle 기본 시간" 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String defaultTimeLabel(String slotKey) {
    final slotTitle = switch (slotKey) {
      'morning' => morning,
      'lunch' => lunch,
      'evening' => evening,
      'bedtime' => bedtime,
      _ => isEnglish ? 'Medication' : '복약',
    };
    return isEnglish ? '$slotTitle default time' : '$slotTitle 기본 시간';
  }

  // 함수이름: medicationAndNotificationSummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "알림 $enabledCount/3개 사용 중 · 기본 복약 시간" 문구를 제공한다.
  // 매개변수:
  // - medicationEnabled (bool): 해당 복약·보호자·채팅 알림의 활성 상태.
  // - caregiverEnabled (bool): 해당 복약·보호자·채팅 알림의 활성 상태.
  // - chatEnabled (bool): 해당 복약·보호자·채팅 알림의 활성 상태.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String medicationAndNotificationSummary({
    required bool medicationEnabled,
    required bool caregiverEnabled,
    required bool chatEnabled,
  }) {
    final enabledCount = [
      medicationEnabled,
      caregiverEnabled,
      chatEnabled,
      // 함수이름: medicationAndNotificationSummary.where callback
      // 함수역할: 접근성·알림·실험 기능·계정 보안 설정에 쓰는 한국어·영어 문구에 대해 `enabled` 조건으로 컬렉션 항목을 판별한다.
      // 매개변수:
      // - enabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
      // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
    ].where((enabled) => enabled).length;
    return isEnglish
        ? '$enabledCount of 3 notification types enabled'
        : '알림 $enabledCount/3개 사용 중 · 기본 복약 시간';
  }

  // 함수이름: displayAndVoiceSummary
  // 함수역할: 글씨 크기·읽기 속도·언어 설정을 표시 라벨로 변환해 하나의 요약으로 묶는다.
  // 매개변수:
  // - fontSize (String): 기준 글씨 크기 또는 선택한 크기 옵션.
  // - readingSpeed (String): 읽어주기에 사용할 음성 속도 옵션.
  // - languageMode (String): 기기 언어 따르기 또는 명시 언어 선택 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String displayAndVoiceSummary({
    required String fontSize,
    required String readingSpeed,
    required String languageMode,
  }) {
    final fontSizeLabel = switch (fontSize) {
      'small' => small,
      'large' => large,
      _ => medium,
    };
    final readingSpeedLabel = switch (readingSpeed) {
      'slow' => slow,
      'fast' => fast,
      _ => medium,
    };
    final languageLabel = switch (languageMode) {
      'system' => followDeviceLanguage,
      'en' => 'English',
      _ => '한국어',
    };
    return '$fontSizeLabel · $readingSpeedLabel · $languageLabel';
  }

  // 함수이름: laboratorySummary
  // 함수역할: 현재 언어와 입력값에 맞춰 "사용 중인 실험 기능 없음" 문구를 제공한다.
  // 매개변수:
  // - multiPillIdentificationEnabled (bool): 여러 알약 사진 식별을 사용할지 여부.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String laboratorySummary({required bool multiPillIdentificationEnabled}) {
    final enabledFeatures = <String>[
      if (multiPillIdentificationEnabled) multiPillIdentificationLabTitle,
    ];
    if (enabledFeatures.isEmpty) {
      return isEnglish ? 'No experimental features enabled' : '사용 중인 실험 기능 없음';
    }
    return enabledFeatures.join(' · ');
  }

  // 함수이름: small
  // 함수역할: 현재 언어와 입력값에 맞춰 "Small" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get small => isEnglish ? 'Small' : '작게';
  // 함수이름: medium
  // 함수역할: 현재 언어와 입력값에 맞춰 "Medium" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medium => isEnglish ? 'Medium' : '중간';
  // 함수이름: large
  // 함수역할: 현재 언어와 입력값에 맞춰 "Large" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get large => isEnglish ? 'Large' : '크게';
  // 함수이름: slow
  // 함수역할: 현재 언어와 입력값에 맞춰 "느리게" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get slow => isEnglish ? 'Slow' : '느리게';
  // 함수이름: fast
  // 함수역할: 현재 언어와 입력값에 맞춰 "빠르게" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get fast => isEnglish ? 'Fast' : '빠르게';
  // 함수이름: preview
  // 함수역할: 현재 언어와 입력값에 맞춰 "미리보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get preview => isEnglish ? 'Preview' : '미리보기';
  // 함수이름: previewSentence
  // 함수역할: 현재 언어와 입력값에 맞춰 "아스피린 100mg을 하루 3회 식후 30분에 복용하세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get previewSentence => isEnglish
      ? 'Take aspirin 100mg three times daily after meals.'
      : '아스피린 100mg을 하루 3회 식후 30분에 복용하세요.';
  // 함수이름: readingSpeedLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "읽기 속도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get readingSpeedLabel => isEnglish ? 'Reading speed' : '읽기 속도';
  // 함수이름: slowLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Slow" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get slowLabel => isEnglish ? 'Slow' : '느림';
  // 함수이름: normalLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Normal" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get normalLabel => isEnglish ? 'Normal' : '보통';
  // 함수이름: fastLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Fast" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get fastLabel => isEnglish ? 'Fast' : '빠름';
  // 함수이름: listenPreview
  // 함수역할: 현재 언어와 입력값에 맞춰 "음성으로 들어보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get listenPreview => isEnglish ? 'Listen' : '음성으로 들어보기';
  // 함수이름: stopPreview
  // 함수역할: 현재 언어와 입력값에 맞춰 "듣기 중지" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get stopPreview => isEnglish ? 'Stop' : '듣기 중지';
  // 함수이름: previewFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "음성 미리보기를 재생하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get previewFailed =>
      isEnglish ? 'Could not play the voice preview.' : '음성 미리보기를 재생하지 못했습니다.';
  // 함수이름: save
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get save => isEnglish ? 'Save' : '저장하기';
  // 함수이름: saving
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  // 함수이름: saved
  // 함수역할: 현재 언어와 입력값에 맞춰 "설정이 저장되었습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saved => isEnglish ? 'Settings saved.' : '설정이 저장되었습니다.';
  // 함수이름: savedOnDeviceOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get savedOnDeviceOnly => isEnglish
      ? 'Saved on this device only. Save again after reconnecting to the server.'
      : '기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요.';
  // 함수이름: saveFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "설정을 저장하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveFailed =>
      isEnglish ? 'Could not save settings.' : '설정을 저장하지 못했습니다.';
  // Function Name: signOut
  // Description: Provides localized wording for "Sign out" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get signOut => isEnglish ? 'Sign out' : '로그아웃';
  // Function Name: guestSignOutTitle
  // Description: Provides localized wording for "Delete guest data and sign out?" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestSignOutTitle =>
      isEnglish ? 'Delete guest data and sign out?' : '게스트 데이터를 삭제하고 로그아웃할까요?';
  // Function Name: guestSignOutMessage
  // Description: Provides localized wording for "Guest medication, schedule, caregiver link, and settings data will be" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestSignOutMessage => isEnglish
      ? 'Guest medication, schedule, caregiver link, and settings data will be '
            'deleted permanently. A later guest login creates a new account.'
      : '게스트 복약정보, 일정, 보호자 연동, 설정 데이터가 모두 영구 삭제됩니다. '
            '나중에 다시 게스트로 로그인하면 새로운 계정이 생성됩니다.';
  // Function Name: signOutFailed
  // Description: Provides localized wording for "Could not sign out safely." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get signOutFailed =>
      isEnglish ? 'Could not sign out safely.' : '안전하게 로그아웃하지 못했습니다.';
  // 함수이름: deleteAccount
  // 함수역할: 현재 언어와 입력값에 맞춰 "계정 데이터 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteAccount => isEnglish ? 'Delete account' : '계정 데이터 삭제';
  // 함수이름: deleteAccountMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약정보, 일정, 보호자 연동, 설정 데이터가 모두 영구 삭제됩니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteAccountMessage => isEnglish
      ? 'All medication, schedule, caregiver link, and settings data will be '
            'deleted permanently. This cannot be undone.'
      : '복약정보, 일정, 보호자 연동, 설정 데이터가 모두 영구 삭제됩니다. '
            '삭제한 데이터는 복구할 수 없습니다.';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';
  // 함수이름: delete
  // 함수역할: 현재 언어와 입력값에 맞춰 "Delete" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get delete => isEnglish ? 'Delete' : '삭제';
  // 함수이름: deleteAccountFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "계정 데이터를 삭제하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteAccountFailed =>
      isEnglish ? 'Could not delete account data.' : '계정 데이터를 삭제하지 못했습니다.';
}
