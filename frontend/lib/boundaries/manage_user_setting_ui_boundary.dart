// 파일명: manage_user_setting_ui_boundary.dart
// 역할: 글씨 크기, 읽기 속도, 언어와 실험실 기능 설정 화면을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../services/tts_service.dart';
import '../theme/medbuddy_theme.dart';

typedef SettingPreviewSpeaker =
    Future<void> Function(
      String text,
      UserSetting userSetting, {
      void Function()? onComplete,
    });
typedef SettingPreviewStopper = Future<void> Function();

// 파일명: manage_user_setting_ui_boundary.dart
// 역할: 글씨 크기, 읽기 속도, 언어 설정 화면을 구성한다.

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
  });

  @override
  State<ManageUserSettingUI> createState() => _ManageUserSettingUIState();
}

class _ManageUserSettingUIState extends State<ManageUserSettingUI> {
  late String _fontSize;
  late String _readingSpeed;
  late String _language;
  late bool _nearbyPharmacyLabEnabled;
  late bool _linkedMedicationChatLabEnabled;
  bool _isSaving = false;
  bool _isPreviewSpeaking = false;
  int _voicePreviewRequestId = 0;
  TTSService? _ownedTtsService;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialSetting.fontSizeOption;
    _readingSpeed = widget.initialSetting.readingSpeedOption;
    _language = widget.initialSetting.language == 'en' ? 'en' : 'ko';
    _nearbyPharmacyLabEnabled = widget.initialSetting.nearbyPharmacyLabEnabled;
    _linkedMedicationChatLabEnabled =
        widget.initialSetting.linkedMedicationChatLabEnabled;
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
      nearbyPharmacyLabEnabled: _nearbyPharmacyLabEnabled,
      linkedMedicationChatLabEnabled: _linkedMedicationChatLabEnabled,
    );
    final platformMediaQuery = MediaQueryData.fromView(View.of(context));
    final systemTextScale = platformMediaQuery.textScaler.scale(16) / 16;
    final selectedTextScale = draftSetting.resolveTextScale(systemTextScale);
    final mediaQuery = MediaQuery.of(context);
    final contentScale = draftSetting.contentTextScale;

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(selectedTextScale),
      ),
      child: Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(40, 26, 40, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CloseButton(
                            tooltip: text.close,
                            onTap: () => Navigator.maybePop(context),
                          ),
                          const SizedBox(height: 22),
                          _SettingTitle(text.fontSizeTitle),
                          const SizedBox(height: 22),
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
                            onSelected: (value) =>
                                setState(() => _fontSize = value),
                          ),
                          const SizedBox(height: 45),
                          _SettingTitle(text.readingSpeedTitle),
                          const SizedBox(height: 22),
                          _OptionRow(
                            options: [
                              _SettingOption(value: 'slow', label: text.slow),
                              _SettingOption(
                                value: 'medium',
                                label: text.medium,
                              ),
                              _SettingOption(value: 'fast', label: text.fast),
                            ],
                            selectedValue: _readingSpeed,
                            contentScale: contentScale,
                            onSelected: (value) =>
                                unawaited(_selectReadingSpeed(value)),
                          ),
                          const SizedBox(height: 45),
                          _SettingTitle(text.languageTitle),
                          const SizedBox(height: 22),
                          _OptionRow(
                            options: const [
                              _SettingOption(value: 'ko', label: '한국어'),
                              _SettingOption(value: 'en', label: 'English'),
                            ],
                            selectedValue: _language,
                            contentScale: contentScale,
                            onSelected: (value) =>
                                setState(() => _language = value),
                          ),
                          const SizedBox(height: 42),
                          _PreviewPanel(
                            text: text,
                            fontSize: _fontSize,
                            readingSpeed: _readingSpeed,
                            isSpeaking: _isPreviewSpeaking,
                            onVoicePreviewRequested: _toggleVoicePreview,
                          ),
                          const SizedBox(height: 42),
                          _SettingTitle(text.laboratoryTitle),
                          const SizedBox(height: 18),
                          _ExperimentalFeatureToggle(
                            switchKey: const ValueKey(
                              'nearbyPharmacyLabSwitch',
                            ),
                            title: text.nearbyPharmacyLabTitle,
                            description: text.nearbyPharmacyLabDescription,
                            enabled: _nearbyPharmacyLabEnabled,
                            onChanged: (enabled) => setState(
                              () => _nearbyPharmacyLabEnabled = enabled,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ExperimentalFeatureToggle(
                            switchKey: const ValueKey(
                              'linkedMedicationChatLabSwitch',
                            ),
                            title: text.linkedMedicationChatLabTitle,
                            description:
                                text.linkedMedicationChatLabDescription,
                            enabled: _linkedMedicationChatLabEnabled,
                            onChanged: (enabled) => setState(
                              () => _linkedMedicationChatLabEnabled = enabled,
                            ),
                          ),
                          if (widget
                              .authenticationControl
                              .phoneAuthenticationEnabled) ...[
                            const SizedBox(height: 28),
                            ListenableBuilder(
                              listenable: widget.authenticationControl,
                              builder: (context, _) => _MfaSettingsPanel(
                                enabled: widget
                                    .authenticationControl
                                    .hasEnrolledSmsMfa,
                                available: widget
                                    .authenticationControl
                                    .canEnrollSmsMfa,
                                onEnrollRequested: _showMfaEnrollment,
                              ),
                            ),
                          ],
                          if (widget.onSignOutRequested != null) ...[
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : _handleSignOutRequested,
                                icon: const Icon(Icons.logout),
                                label: Text(text.signOut),
                              ),
                            ),
                          ],
                          if (widget.onDeleteAccountRequested != null) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: MedBuddyColors.danger,
                                  side: const BorderSide(
                                    color: MedBuddyColors.danger,
                                  ),
                                ),
                                onPressed: _isSaving
                                    ? null
                                    : _confirmAccountDeletion,
                                icon: const Icon(Icons.delete_forever_outlined),
                                label: Text(text.deleteAccount),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
    );
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
      final saveResult = await widget.onSettingSaveRequested(
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

class _CloseButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _CloseButton({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: ExcludeSemantics(
        child: IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          tooltip: tooltip,
          onPressed: onTap,
          icon: const Icon(Icons.close, color: Color(0xFF4A5565), size: 31),
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

  String get close => isEnglish ? 'Close' : '닫기';
  String get fontSizeTitle => isEnglish ? 'Text Size' : '글씨크기';
  String get readingSpeedTitle => isEnglish ? 'Reading Speed' : '읽기속도';
  String get languageTitle => isEnglish ? 'Language' : '언어';
  String get laboratoryTitle => isEnglish ? 'Labs' : '실험실';
  String get nearbyPharmacyLabTitle =>
      isEnglish ? 'Nearby open pharmacies' : '근처 운영 약국';
  String get nearbyPharmacyLabDescription => isEnglish
      ? 'Show the experimental nearby pharmacy feature on the home screen.'
      : '현재 위치 주변의 영업 중·24시간 약국 기능을 메인 화면에 표시합니다.';
  String get linkedMedicationChatLabTitle =>
      isEnglish ? 'Medication conversation' : '복약 대화';
  String get linkedMedicationChatLabDescription => isEnglish
      ? 'Let linked patients and caregivers discuss an active medication.'
      : '복용 중인 약을 선택해 환자와 보호자가 대화할 수 있게 표시합니다.';
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
