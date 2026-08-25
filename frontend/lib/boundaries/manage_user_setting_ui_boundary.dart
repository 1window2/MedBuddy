// 파일명: manage_user_setting_ui_boundary.dart
// 역할: 화면·음성, 실험 기능과 계정 설정 화면을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../services/tts_service.dart';
import '../theme/medbuddy_theme.dart';
import 'set_notification_ui_boundary.dart';

typedef SettingPreviewSpeaker =
    Future<void> Function(
      String text,
      UserSetting userSetting, {
      void Function()? onComplete,
    });
typedef SettingPreviewStopper = Future<void> Function();
typedef ExtendedUserSettingSaver =
    Future<UserSettingSaveResult> Function(UserSetting setting);

// 클래스명: ManageUserSettingUI
// 역할: 사용자가 접근성 관련 표시 설정을 선택하고 저장할 수 있게 한다.
// 주요 책임:
// - 현재 저장된 설정을 초기 선택값으로 표시한다.
// - 글씨 크기와 언어 변경을 현재 설정 화면에 즉시 반영한다.
// - 저장 버튼을 통해 변경값을 ViewModel로 전달한다.
class ManageUserSettingUI extends StatefulWidget {
  final UserSetting initialSetting;
  final AuthenticationControl authenticationControl;
  final Future<void> Function()? onSignOutRequested;
  final Future<void> Function()? onDeleteAccountRequested;
  final SettingPreviewSpeaker? previewSpeaker;
  final SettingPreviewStopper? previewStopper;
  final Future<void> Function(bool enabled)?
  onNearbyPharmacyLabSettingSaveRequested;
  final Future<void> Function(bool enabled)?
  onLinkedMedicationChatLabSettingSaveRequested;
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

  const ManageUserSettingUI({
    super.key,
    required this.initialSetting,
    required this.authenticationControl,
    required this.onSettingSaveRequested,
    this.onSignOutRequested,
    this.onDeleteAccountRequested,
    this.previewSpeaker,
    this.previewStopper,
    this.onNearbyPharmacyLabSettingSaveRequested,
    this.onLinkedMedicationChatLabSettingSaveRequested,
    this.onMultiPillIdentificationLabSettingSaveRequested,
    this.onExtendedSettingSaveRequested,
    this.onMedicationScheduleRequested,
    this.onDeviceNotificationSettingsRequested,
  });

  @override
  State<ManageUserSettingUI> createState() => _ManageUserSettingUIState();
}

enum _SettingSection {
  overview,
  medicationAndNotifications,
  displayAndVoice,
  laboratory,
  account,
}

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
  late bool _nearbyPharmacyLabEnabled;
  late bool _linkedMedicationChatLabEnabled;
  late bool _multiPillIdentificationLabEnabled;
  bool _isSaving = false;
  bool _isPreviewSpeaking = false;
  int _voicePreviewRequestId = 0;
  TTSService? _ownedTtsService;
  _SettingSection _selectedSection = _SettingSection.overview;

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
    _nearbyPharmacyLabEnabled = widget.initialSetting.nearbyPharmacyLabEnabled;
    _linkedMedicationChatLabEnabled =
        widget.initialSetting.linkedMedicationChatLabEnabled;
    _multiPillIdentificationLabEnabled =
        widget.initialSetting.multiPillIdentificationLabEnabled;
    if (widget.previewSpeaker == null) {
      _ownedTtsService = TTSService();
    }
  }

  @override
  void dispose() {
    final ownedTtsService = _ownedTtsService;
    if (ownedTtsService != null) {
      unawaited(ownedTtsService.stop());
    }
    super.dispose();
  }

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
      nearbyPharmacyLabEnabled: _nearbyPharmacyLabEnabled,
      linkedMedicationChatLabEnabled: _linkedMedicationChatLabEnabled,
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

  // 함수명: _buildSelectedSection
  // 역할:
  // - 설정 홈과 각 설정 영역을 동일한 상태값으로 전환해 저장 전 선택을 유지한다.
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
          nearbyPharmacyEnabled: _nearbyPharmacyLabEnabled,
          medicationChatEnabled: _linkedMedicationChatLabEnabled,
          multiPillIdentificationEnabled: _multiPillIdentificationLabEnabled,
        ),
        onSectionSelected: (section) {
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

  // 함수명: _buildMedicationAndNotificationSettings
  // 역할: 전체 알림 정책, 신규 일정 기본 시각과 잠금 화면 공개 범위를 구성한다.
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
          onChanged: (enabled) =>
              setState(() => _medicationNotificationsEnabled = enabled),
        ),
        const SizedBox(height: 12),
        _SettingToggle(
          switchKey: const ValueKey('caregiverNotificationsSwitch'),
          title: text.caregiverNotificationsTitle,
          description: text.caregiverNotificationsDescription,
          enabled: _caregiverNotificationsEnabled,
          onChanged: (enabled) =>
              setState(() => _caregiverNotificationsEnabled = enabled),
        ),
        const SizedBox(height: 12),
        _SettingToggle(
          switchKey: const ValueKey('chatNotificationsSwitch'),
          title: text.chatNotificationsTitle,
          description: text.chatNotificationsDescription,
          enabled: _chatNotificationsEnabled,
          onChanged: (enabled) =>
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
          onSelected: (value) =>
              setState(() => _notificationDetailMode = value),
        ),
      ],
    );
  }

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

  Widget _buildLaboratorySettings(_SettingText text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingTitle(text.laboratoryTitle),
        const SizedBox(height: 24),
        _ExperimentalFeatureToggle(
          switchKey: const ValueKey('nearbyPharmacyLabSwitch'),
          title: text.nearbyPharmacyLabTitle,
          description: text.nearbyPharmacyLabDescription,
          enabled: _nearbyPharmacyLabEnabled,
          onChanged: (enabled) =>
              setState(() => _nearbyPharmacyLabEnabled = enabled),
        ),
        const SizedBox(height: 14),
        _ExperimentalFeatureToggle(
          switchKey: const ValueKey('linkedMedicationChatLabSwitch'),
          title: text.linkedMedicationChatLabTitle,
          description: text.linkedMedicationChatLabDescription,
          enabled: _linkedMedicationChatLabEnabled,
          onChanged: (enabled) =>
              setState(() => _linkedMedicationChatLabEnabled = enabled),
        ),
        const SizedBox(height: 14),
        _ExperimentalFeatureToggle(
          switchKey: const ValueKey('multiPillIdentificationLabSwitch'),
          title: text.multiPillIdentificationLabTitle,
          description: text.multiPillIdentificationLabDescription,
          enabled: _multiPillIdentificationLabEnabled,
          onChanged: (enabled) =>
              setState(() => _multiPillIdentificationLabEnabled = enabled),
        ),
      ],
    );
  }

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

  String _maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) {
      return email;
    }
    final localPart = email.substring(0, atIndex);
    final visibleLength = localPart.length <= 2 ? 1 : 2;
    return '${localPart.substring(0, visibleLength)}***${email.substring(atIndex)}';
  }

  String _maskPhoneNumber(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      return phoneNumber;
    }
    return '${digits.substring(0, digits.length - 7)}***${digits.substring(digits.length - 4)}';
  }

  void _handleBackRequested() {
    if (_selectedSection == _SettingSection.overview) {
      Navigator.maybePop(context);
      return;
    }
    _showSettingsOverview();
  }

  void _showSettingsOverview() {
    if (_selectedSection == _SettingSection.displayAndVoice) {
      unawaited(_stopVoicePreview());
    }
    setState(() => _selectedSection = _SettingSection.overview);
  }

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
    nearbyPharmacyLabEnabled: _nearbyPharmacyLabEnabled,
    linkedMedicationChatLabEnabled: _linkedMedicationChatLabEnabled,
    multiPillIdentificationLabEnabled: _multiPillIdentificationLabEnabled,
  );

  // 함수명: _selectLanguageMode
  // 역할: 선택한 언어 모드를 즉시 현재 설정 화면의 표시 언어에 반영한다.
  void _selectLanguageMode(String languageMode) {
    setState(() {
      _languageMode = languageMode;
      _language = AppLanguageControl.resolveLanguage(languageMode);
    });
  }

  // 함수명: _selectDefaultMedicationTime
  // 역할: 기존 복약 알림과 같은 시간 선택기를 사용해 신규 일정 기본 시각을 바꾼다.
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

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts.first) ?? 8 : 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

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

  // 함수명: _selectReadingSpeed
  // 함수역할:
  // - 재생 중인 미리보기를 중지한 뒤 새 읽기 속도를 선택한다.
  // 매개변수:
  // - value: slow, medium, fast 중 선택한 속도
  // 반환값:
  // - 없음
  Future<void> _selectReadingSpeed(String value) async {
    await _stopVoicePreview();
    if (!mounted) {
      return;
    }
    setState(() => _readingSpeed = value);
  }

  // 함수명: _toggleVoicePreview
  // 함수역할:
  // - 현재 설정된 언어와 읽기 속도로 예시 문장을 재생하거나 중지한다.
  // 반환값:
  // - 없음
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
    setState(() => _isPreviewSpeaking = true);

    try {
      final speaker = widget.previewSpeaker ?? _ownedTtsService!.speak;
      await speaker(
        text.previewSentence,
        previewSetting,
        onComplete: () => _finishVoicePreview(requestId),
      );
    } catch (_) {
      if (!mounted || requestId != _voicePreviewRequestId) {
        return;
      }
      setState(() => _isPreviewSpeaking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.previewFailed)));
    }
  }

  // 함수명: _stopVoicePreview
  // 함수역할:
  // - 미리보기 음성을 중지하고 버튼 상태를 재생 가능 상태로 되돌린다.
  // 반환값:
  // - 없음
  Future<void> _stopVoicePreview() async {
    // 사용자가 중지를 누르면 진행 중인 재생 요청을 먼저 무효화해 취소를 오류와 구분한다.
    _voicePreviewRequestId += 1;
    if (mounted && _isPreviewSpeaking) {
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

  // 함수명: _finishVoicePreview
  // 함수역할:
  // - TTS 엔진이 재생 완료를 알리면 미리보기 버튼 상태를 복구한다.
  // 반환값:
  // - 없음
  void _finishVoicePreview(int requestId) {
    if (!mounted ||
        requestId != _voicePreviewRequestId ||
        !_isPreviewSpeaking) {
      return;
    }
    setState(() => _isPreviewSpeaking = false);
  }

  // 함수이름: _handleSaveRequested
  // 함수역할:
  // - 설정 저장 요청을 한 번만 실행하고 실패 시 버튼 상태를 복구한다.
  // 반환값:
  // - 없음
  Future<void> _handleSaveRequested() async {
    if (_isSaving) {
      return;
    }

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
      await widget.onNearbyPharmacyLabSettingSaveRequested?.call(
        _nearbyPharmacyLabEnabled,
      );
      await widget.onLinkedMedicationChatLabSettingSaveRequested?.call(
        _linkedMedicationChatLabEnabled,
      );
      await widget.onMultiPillIdentificationLabSettingSaveRequested?.call(
        _multiPillIdentificationLabEnabled,
      );
      if (!mounted) {
        return;
      }

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

      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.saveFailed)));
    }
  }

  // 함수이름: _handleSignOutRequested
  // 함수역할:
  // - 익명 사용자의 로그아웃 시 게스트 데이터가 영구 삭제됨을 안내한다.
  // - 로그아웃 또는 삭제 요청 중에는 중복 입력을 차단한다.
  // 반환값:
  // - 취소, 초기 화면 이동 또는 오류 안내가 끝나면 완료된다.
  Future<void> _handleSignOutRequested() async {
    if (_isSaving) {
      return;
    }

    final text = _SettingText(_language);
    if (widget.authenticationControl.isAnonymous) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(text.guestSignOutTitle),
          content: Text(text.guestSignOutMessage),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: MedBuddyColors.textStrong,
              ),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(text.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.danger,
              ),
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

    setState(() => _isSaving = true);
    try {
      await widget.onSignOutRequested?.call();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.signOutFailed)));
    }
  }

  Future<void> _showMfaEnrollment() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _MfaEnrollmentDialog(control: widget.authenticationControl),
    );
  }

  // 함수명: _confirmAccountDeletion
  // 역할:
  // - 데이터 삭제의 비가역성을 알리고 명시적으로 확인한 경우에만 삭제한다.
  Future<void> _confirmAccountDeletion() async {
    final text = _SettingText(_language);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(text.deleteAccount),
        content: Text(text.deleteAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(text.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MedBuddyColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(text.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.onDeleteAccountRequested?.call();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }
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

class _AccountPresentation {
  final String greeting;
  final String detail;

  const _AccountPresentation({required this.greeting, required this.detail});
}

class _SettingsOverview extends StatelessWidget {
  final _SettingText text;
  final _AccountPresentation accountPresentation;
  final String medicationAndNotificationSummary;
  final String displayAndVoiceSummary;
  final String laboratorySummary;
  final ValueChanged<_SettingSection> onSectionSelected;

  const _SettingsOverview({
    required this.text,
    required this.accountPresentation,
    required this.medicationAndNotificationSummary,
    required this.displayAndVoiceSummary,
    required this.laboratorySummary,
    required this.onSectionSelected,
  });

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
          onTap: () =>
              onSectionSelected(_SettingSection.medicationAndNotifications),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsDisplayAndVoiceMenu'),
          icon: Icons.text_fields_rounded,
          title: text.displayAndVoiceTitle,
          summary: displayAndVoiceSummary,
          onTap: () => onSectionSelected(_SettingSection.displayAndVoice),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsLaboratoryMenu'),
          icon: Icons.science_outlined,
          title: text.laboratoryTitle,
          summary: laboratorySummary,
          onTap: () => onSectionSelected(_SettingSection.laboratory),
        ),
        const SizedBox(height: 14),
        _SettingsMenuTile(
          tileKey: const ValueKey('settingsAccountMenu'),
          icon: Icons.manage_accounts_outlined,
          title: text.accountTitle,
          summary: text.accountMenuSummary,
          onTap: () => onSectionSelected(_SettingSection.account),
        ),
      ],
    );
  }
}

class _AccountWelcomePanel extends StatelessWidget {
  final _AccountPresentation presentation;
  final bool compact;

  const _AccountWelcomePanel({
    required this.presentation,
    this.compact = false,
  });

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

class _SettingsMenuTile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  const _SettingsMenuTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

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

class _MfaSettingsPanel extends StatelessWidget {
  final bool enabled;
  final bool available;
  final VoidCallback onEnrollRequested;

  const _MfaSettingsPanel({
    required this.enabled,
    required this.available,
    required this.onEnrollRequested,
  });

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

class _MfaEnrollmentDialog extends StatefulWidget {
  final AuthenticationControl control;

  const _MfaEnrollmentDialog({required this.control});

  @override
  State<_MfaEnrollmentDialog> createState() => _MfaEnrollmentDialogState();
}

class _MfaEnrollmentDialogState extends State<_MfaEnrollmentDialog> {
  final _phoneController = TextEditingController(text: '+82');
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.control,
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
                  : () {
                      widget.control.cancelSmsChallenge();
                      Navigator.pop(context);
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: widget.control.isBusy
                  ? null
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

class _SettingsBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _SettingsBackButton({required this.tooltip, required this.onTap});

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

class _SettingSaveFooter extends StatelessWidget {
  final _SettingText text;
  final bool isSaving;
  final Future<void> Function() onSaveRequested;

  const _SettingSaveFooter({
    required this.text,
    required this.isSaving,
    required this.onSaveRequested,
  });

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

class _SettingTitle extends StatelessWidget {
  final String text;

  const _SettingTitle(this.text);

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

class _SettingFieldTitle extends StatelessWidget {
  final String text;

  const _SettingFieldTitle(this.text);

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

class _ExperimentalFeatureToggle extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ExperimentalFeatureToggle({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

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

class _SettingToggle extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

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

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

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

class _DefaultMedicationTimePanel extends StatelessWidget {
  final _SettingText text;
  final UserSetting userSetting;
  final String morningTime;
  final String lunchTime;
  final String eveningTime;
  final String bedtime;
  final ValueChanged<String> onTimeRequested;

  const _DefaultMedicationTimePanel({
    required this.text,
    required this.userSetting,
    required this.morningTime,
    required this.lunchTime,
    required this.eveningTime,
    required this.bedtime,
    required this.onTimeRequested,
  });

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

class _StackedOptionList extends StatelessWidget {
  final List<_SettingOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  const _StackedOptionList({
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

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

class _OptionRow extends StatelessWidget {
  final List<_SettingOption> options;
  final String selectedValue;
  final double contentScale;
  final ValueChanged<String> onSelected;

  const _OptionRow({
    required this.options,
    required this.selectedValue,
    required this.contentScale,
    required this.onSelected,
  });

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
              onTap: () => onSelected(options[index].value),
            ),
          ),
          if (index != options.length - 1) const SizedBox(width: 11),
        ],
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final _SettingOption option;
  final bool selected;
  final double contentScale;
  final VoidCallback? onTap;

  const _SegmentButton({
    required this.option,
    required this.selected,
    required this.contentScale,
    required this.onTap,
  });

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

class _PreviewPanel extends StatelessWidget {
  final _SettingText text;
  final String fontSize;
  final String readingSpeed;
  final bool isSpeaking;
  final VoidCallback onVoicePreviewRequested;

  const _PreviewPanel({
    required this.text,
    required this.fontSize,
    required this.readingSpeed,
    required this.isSpeaking,
    required this.onVoicePreviewRequested,
  });

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

class _SettingOption {
  final String value;
  final String label;

  final double? labelFontSize;

  const _SettingOption({
    required this.value,
    required this.label,

    this.labelFontSize,
  });
}

class _SettingText {
  final String language;

  const _SettingText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get settingsTitle => isEnglish ? 'Settings' : '환경설정';
  String get medicationAndNotificationsTitle =>
      isEnglish ? 'Medication & Notifications' : '복약 및 알림';
  String get displayAndVoiceTitle => isEnglish ? 'Display & Voice' : '화면 및 음성';
  String get fontSizeTitle => isEnglish ? 'Text Size' : '글씨크기';
  String get readingSpeedTitle => isEnglish ? 'Reading Speed' : '읽기속도';
  String get languageTitle => isEnglish ? 'Language' : '언어';
  String get laboratoryTitle => isEnglish ? 'Labs' : '실험실';
  String get accountTitle => isEnglish ? 'Account' : '계정';
  String get defaultUserName => isEnglish ? 'MedBuddy User' : '사용자';
  String welcome(String name) => isEnglish ? 'Welcome, $name' : '$name님, 안녕하세요';
  String get guestAccount =>
      isEnglish ? 'Using a guest account' : '게스트 계정으로 사용 중';
  String get localDemoAccount => isEnglish ? 'Local demo account' : '로컬 데모 계정';
  String get signedInAccount =>
      isEnglish ? 'Signed in to MedBuddy' : 'MedBuddy 계정으로 로그인됨';
  String get accountMenuSummary =>
      isEnglish ? 'Sign-in, security, and account data' : '로그인, 보안 및 계정 데이터 관리';
  String get noAccountActions => isEnglish
      ? 'No additional account actions are available in this mode.'
      : '현재 실행 모드에서는 추가로 변경할 계정 설정이 없습니다.';
  String get nearbyPharmacyLabTitle =>
      isEnglish ? 'Nearby open pharmacies' : '근처 운영 약국';
  String get nearbyPharmacyLabDescription => isEnglish
      ? 'Show the experimental nearby pharmacy feature on the home screen.'
      : '현재 위치 주변의 운영 약국 기능을 메인 화면에 표시합니다.';
  String get linkedMedicationChatLabTitle =>
      isEnglish ? 'Medication conversation' : '복약 대화';
  String get linkedMedicationChatLabDescription => isEnglish
      ? 'Let linked patients and caregivers discuss an active medication.'
      : '복용 중인 약을 선택해 환자와 보호자가 대화할 수 있게 표시합니다.';
  String get multiPillIdentificationLabTitle =>
      isEnglish ? 'Multi-pill batch identification' : '다중 알약 일괄 식별';
  String get multiPillIdentificationLabDescription => isEnglish
      ? 'Add one photo per pill and review several identification results together.'
      : '알약마다 사진을 한 장씩 추가해 여러 식별 결과를 한 번에 검토합니다.';
  String get medicationNotificationsTitle =>
      isEnglish ? 'My medication reminders' : '내 복약 알림';
  String get medicationNotificationsDescription => isEnglish
      ? 'Receive reminders for your scheduled medication times.'
      : '복용 시간에 맞춰 내 휴대폰으로 알림을 받습니다.';
  String get caregiverNotificationsTitle =>
      isEnglish ? 'Caregiver updates' : '보호자 알림';
  String get caregiverNotificationsDescription => isEnglish
      ? 'Receive medication updates for linked patients.'
      : '연동된 환자의 복약 상태 알림을 받습니다.';
  String get chatNotificationsTitle =>
      isEnglish ? 'Chat notifications' : '채팅 알림';
  String get chatNotificationsDescription => isEnglish
      ? 'Receive notifications for new medication conversations.'
      : '복약 대화에 새 메시지가 오면 알림을 받습니다.';
  String get deviceNotificationSettingsTitle =>
      isEnglish ? 'Phone notification settings' : '휴대폰 알림 설정';
  String get deviceNotificationSettingsDescription => isEnglish
      ? 'Review notification permission and lock-screen behavior.'
      : '알림 권한과 휴대폰 잠금 화면 표시를 확인합니다.';
  String get deviceNotificationSettingsFailed => isEnglish
      ? 'Could not open the phone notification settings.'
      : '휴대폰 알림 설정을 열지 못했습니다.';
  String get defaultMedicationTimeTitle =>
      isEnglish ? 'Default medication times' : '기본 복약 시간';
  String get defaultMedicationTimeDescription => isEnglish
      ? 'Used only as the initial time for newly added medication schedules.'
      : '새로 등록하는 복약 일정의 처음 시각으로만 사용합니다.';
  String get detailedScheduleSettingsTitle =>
      isEnglish ? 'Schedule-specific settings' : '시간대별 세부 설정';
  String get detailedScheduleSettingsDescription => isEnglish
      ? 'Open today’s medication schedule to adjust existing reminders.'
      : '오늘의 복약 일정에서 기존 알림 시각을 따로 조정합니다.';
  String get notificationPrivacyTitle =>
      isEnglish ? 'Lock-screen privacy' : '잠금 화면 개인정보';
  String get notificationPrivacyDescription => isEnglish
      ? 'Choose whether medication names and chat messages appear in notifications.'
      : '알림에 약 이름과 채팅 내용을 표시할지 선택합니다.';
  String get notificationPrivacyFull =>
      isEnglish ? 'Show medication names and messages' : '약 이름과 메시지 모두 표시';
  String get notificationPrivacyTypeOnly =>
      isEnglish ? 'Show notification type only' : '알림 종류만 표시';
  String get followDeviceLanguage =>
      isEnglish ? 'Use device language' : '기기 설정 따르기';
  String get timeFormatTitle => isEnglish ? 'Time display' : '시간 표시';
  String get twelveHourTime => isEnglish ? 'AM/PM' : '오전/오후';
  String get twentyFourHourTime => isEnglish ? '24-hour' : '24시간제';
  String get morning => isEnglish ? 'Morning' : '아침';
  String get lunch => isEnglish ? 'Lunch' : '점심';
  String get evening => isEnglish ? 'Evening' : '저녁';
  String get bedtime => isEnglish ? 'Bedtime' : '취침 전';
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

  String medicationAndNotificationSummary({
    required bool medicationEnabled,
    required bool caregiverEnabled,
    required bool chatEnabled,
  }) {
    final enabledCount = [
      medicationEnabled,
      caregiverEnabled,
      chatEnabled,
    ].where((enabled) => enabled).length;
    return isEnglish
        ? '$enabledCount of 3 notification types enabled'
        : '알림 $enabledCount/3개 사용 중 · 기본 복약 시간';
  }

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

  String laboratorySummary({
    required bool nearbyPharmacyEnabled,
    required bool medicationChatEnabled,
    required bool multiPillIdentificationEnabled,
  }) {
    final enabledFeatures = <String>[
      if (nearbyPharmacyEnabled) nearbyPharmacyLabTitle,
      if (medicationChatEnabled) linkedMedicationChatLabTitle,
      if (multiPillIdentificationEnabled) multiPillIdentificationLabTitle,
    ];
    if (enabledFeatures.isEmpty) {
      return isEnglish ? 'No experimental features enabled' : '사용 중인 실험 기능 없음';
    }
    return enabledFeatures.join(' · ');
  }

  String get small => isEnglish ? 'Small' : '작게';
  String get medium => isEnglish ? 'Medium' : '중간';
  String get large => isEnglish ? 'Large' : '크게';
  String get slow => isEnglish ? 'Slow' : '느리게';
  String get fast => isEnglish ? 'Fast' : '빠르게';
  String get preview => isEnglish ? 'Preview' : '미리보기';
  String get previewSentence => isEnglish
      ? 'Take aspirin 100mg three times daily after meals.'
      : '아스피린 100mg을 하루 3회 식후 30분에 복용하세요.';
  String get readingSpeedLabel => isEnglish ? 'Reading speed' : '읽기 속도';
  String get slowLabel => isEnglish ? 'Slow' : '느림';
  String get normalLabel => isEnglish ? 'Normal' : '보통';
  String get fastLabel => isEnglish ? 'Fast' : '빠름';
  String get listenPreview => isEnglish ? 'Listen' : '음성으로 들어보기';
  String get stopPreview => isEnglish ? 'Stop' : '듣기 중지';
  String get previewFailed =>
      isEnglish ? 'Could not play the voice preview.' : '음성 미리보기를 재생하지 못했습니다.';
  String get save => isEnglish ? 'Save' : '저장하기';
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  String get saved => isEnglish ? 'Settings saved.' : '설정이 저장되었습니다.';
  String get savedOnDeviceOnly => isEnglish
      ? 'Saved on this device only. Save again after reconnecting to the server.'
      : '기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요.';
  String get saveFailed =>
      isEnglish ? 'Could not save settings.' : '설정을 저장하지 못했습니다.';
  String get signOut => isEnglish ? 'Sign out' : '로그아웃';
  String get guestSignOutTitle =>
      isEnglish ? 'Delete guest data and sign out?' : '게스트 데이터를 삭제하고 로그아웃할까요?';
  String get guestSignOutMessage => isEnglish
      ? 'Guest medication, schedule, caregiver link, and settings data will be '
            'deleted permanently. A later guest login creates a new account.'
      : '게스트 복약정보, 일정, 보호자 연동, 설정 데이터가 모두 영구 삭제됩니다. '
            '나중에 다시 게스트로 로그인하면 새로운 계정이 생성됩니다.';
  String get signOutFailed =>
      isEnglish ? 'Could not sign out safely.' : '안전하게 로그아웃하지 못했습니다.';
  String get deleteAccount => isEnglish ? 'Delete account' : '계정 데이터 삭제';
  String get deleteAccountMessage => isEnglish
      ? 'All medication, schedule, caregiver link, and settings data will be '
            'deleted permanently. This cannot be undone.'
      : '복약정보, 일정, 보호자 연동, 설정 데이터가 모두 영구 삭제됩니다. '
            '삭제한 데이터는 복구할 수 없습니다.';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get delete => isEnglish ? 'Delete' : '삭제';
  String get deleteAccountFailed =>
      isEnglish ? 'Could not delete account data.' : '계정 데이터를 삭제하지 못했습니다.';
}
