import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controls/patient_guardian_link_control.dart';
import '../controls/set_guardian_alert_setting_control.dart';
import '../entities/guardian_alert_setting_entity.dart';
import '../entities/patient_guardian_link_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'set_guardian_alert_setting_ui_boundary.dart';

// 파일명: patient_guardian_link_ui_boundary.dart
// 역할: 환자와 보호자 연동을 관리하는 화면을 구성한다.

// 클래스명: PatientGuardianLinkUI
// 역할: 환자 코드 생성, 보호자 코드 등록, 연동 목록 조회/해제를 한 화면에서 처리한다.
// 주요 책임:
// - 현재 사용자 해시 기준 연동 목록을 조회한다.
// - 환자용 임시 코드를 생성해 보호자에게 전달할 수 있게 한다.
// - 보호자가 환자 코드를 입력해 연동을 등록할 수 있게 한다.
class PatientGuardianLinkUI extends StatefulWidget {
  final String initialUserHash;
  final void Function({
    required String patientHash,
    String? userHash,
    required String role,
  })? onMedicationScopeSelected;

  const PatientGuardianLinkUI({
    super.key,
    this.initialUserHash = PatientHash.defaultPatientHash,
    this.onMedicationScopeSelected,
  });

  @override
  State<PatientGuardianLinkUI> createState() => _PatientGuardianLinkUIState();
}

class _PatientGuardianLinkUIState extends State<PatientGuardianLinkUI> {
  late final TextEditingController _userHashController;
  late final TextEditingController _patientCodeController;

  List<PatientGuardianLink> _links = const [];
  Map<String, GuardianAlertSetting> _guardianAlertSettings = const {};
  Set<String> _guardianAlertLoadingKeys = const {};
  String _statusMessage =
      '\uC5F0\uB3D9 \uC815\uBCF4\uB97C \uBD88\uB7EC\uC624\uB294 \uC911\uC785\uB2C8\uB2E4.';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _userHashController = TextEditingController(text: widget.initialUserHash);
    _patientCodeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLinks();
    });
  }

  @override
  void dispose() {
    _userHashController.dispose();
    _patientCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 24, 42, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: '닫기',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 42,
                  height: 42,
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.close,
                  color: MedBuddyColors.textMuted,
                  size: 30,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                '환자/보호자 연동하기',
                style: TextStyle(
                  color: Color(0xFF0A0A0A),
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 26),
              _StatusCard(
                statusMessage: _statusMessage,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _LinkListCard(
                  links: _links,
                  currentUserHash: _currentUserHash,
                  guardianAlertSettings: _guardianAlertSettings,
                  guardianAlertLoadingKeys: _guardianAlertLoadingKeys,
                  onUnlinkRequested: _requestUnlink,
                  onGuardianAlertChanged: _updateGuardianAlertSetting,
                ),
              ),
              const SizedBox(height: 20),
              _LinkActionFooter(
                onGeneratePatientCodeRequested: _requestPatientCode,
                onRegisterPatientRequested: _showRegisterPatientDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshLinks() async {
    await _runLinkAction(() async {
      final control = _buildControl();
      try {
        final links = await control.requestPatientGuardianLink();
        if (!mounted) {
          return;
        }
        setState(() {
          _links = links;
          _statusMessage = links.isEmpty
              ? '\uC800\uC7A5\uB41C \uC5F0\uB3D9\uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
              : '\uCD1D ${links.length}\uAC1C\uC758 \uC5F0\uB3D9\uC774 \uC788\uC2B5\uB2C8\uB2E4.';
        });
        _applyMedicationScope(links);
        await _requestGuardianAlertSettings(links);
      } finally {
        control.dispose();
      }
    });
  }

  Future<void> _requestPatientCode() async {
    var shouldRefreshLinks = false;
    await _runLinkAction(() async {
      final control = _buildControl();
      try {
        final patientCode = await control.requestPatientCode();
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage =
              '\uBCF4\uD638\uC790\uC5D0\uAC8C \uACF5\uC720\uD560 \uC5F0\uB3D9 \uCF54\uB4DC\uB97C \uC0DD\uC131\uD588\uC2B5\uB2C8\uB2E4.';
        });
        await _showPatientCodeDialog(patientCode);
        shouldRefreshLinks = mounted;
      } finally {
        control.dispose();
      }
    });
    if (shouldRefreshLinks) {
      await _refreshLinks();
    }
  }

  Future<bool> _registerPatientCode() async {
    final patientCode = _patientCodeController.text.trim();
    if (patientCode.isEmpty) {
      setState(() {
        _statusMessage =
            '\uB4F1\uB85D\uD560 \uD658\uC790 \uC5F0\uB3D9 \uCF54\uB4DC\uB97C \uC785\uB825\uD574 \uC8FC\uC138\uC694.';
      });
      return false;
    }

    var registered = false;
    await _runLinkAction(() async {
      final control = _buildControl();
      try {
        await control.registerPatientCode(patientCode);
        final links = await control.requestLinkPage();
        if (!mounted) {
          return;
        }
        setState(() {
          _links = links;
          _patientCodeController.clear();
          _statusMessage =
              '\uD658\uC790-\uBCF4\uD638\uC790 \uC5F0\uB3D9\uC744 \uB4F1\uB85D\uD588\uC2B5\uB2C8\uB2E4.';
          registered = true;
        });
        _applyMedicationScope(links);
        await _requestGuardianAlertSettings(links);
      } finally {
        control.dispose();
      }
    });
    return registered;
  }

  Future<void> _requestUnlink(PatientGuardianLink link) async {
    final linkID = link.linkID;
    if (linkID == null) {
      setState(() {
        _statusMessage =
            '\uC5F0\uB3D9 \uC2DD\uBCC4\uC790\uAC00 \uC5C6\uC5B4 \uD574\uC81C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.';
      });
      return;
    }

    await _runLinkAction(() async {
      final control = _buildControl();
      try {
        await control.requestUnlink(linkID);
        final links = await control.requestLinkPage();
        if (!mounted) {
          return;
        }
        setState(() {
          _links = links;
          _guardianAlertSettings = Map<String, GuardianAlertSetting>.from(
            _guardianAlertSettings,
          )..remove(_alertSettingKeyForLink(link));
          _statusMessage =
              '\uD658\uC790-\uBCF4\uD638\uC790 \uC5F0\uB3D9\uC744 \uD574\uC81C\uD588\uC2B5\uB2C8\uB2E4.';
        });
        _applyMedicationScope(links);
        await _requestGuardianAlertSettings(links);
      } finally {
        control.dispose();
      }
    });
  }

  Future<void> _runLinkAction(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  PatientGuardianLinkControl _buildControl() {
    return PatientGuardianLinkControl(userHash: _currentUserHash);
  }

  Future<void> _requestGuardianAlertSettings(
    List<PatientGuardianLink> links,
  ) async {
    final currentUserHash = _currentUserHash;
    final guardianLinks = links
        .where(
          (link) =>
              link.linked &&
              link.guardianID == currentUserHash &&
              link.patientID.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (guardianLinks.isEmpty) {
      if (mounted) {
        setState(() {
          _guardianAlertSettings = const {};
          _guardianAlertLoadingKeys = const {};
        });
      }
      return;
    }

    final loadingKeys = guardianLinks.map(_alertSettingKeyForLink).toSet();
    if (mounted) {
      setState(() {
        _guardianAlertLoadingKeys = {
          ..._guardianAlertLoadingKeys,
          ...loadingKeys,
        };
      });
    }

    final control = SetGuardianAlertSetting(guardianHash: currentUserHash);
    final nextSettings = <String, GuardianAlertSetting>{};
    String? errorMessage;
    try {
      for (final link in guardianLinks) {
        try {
          nextSettings[_alertSettingKeyForLink(link)] =
              await control.requestGuardianAlertSetting(
            patientHash: link.patientID,
          );
        } catch (error) {
          errorMessage = error.toString().replaceFirst('Bad state: ', '');
        }
      }
    } finally {
      control.dispose();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _guardianAlertSettings = {
        ..._guardianAlertSettings,
        ...nextSettings,
      };
      _guardianAlertLoadingKeys =
          _guardianAlertLoadingKeys.difference(loadingKeys);
      if (errorMessage != null) {
        _statusMessage = errorMessage;
      }
    });
  }

  Future<void> _updateGuardianAlertSetting(
    PatientGuardianLink link,
    bool enabled,
  ) async {
    final currentUserHash = _currentUserHash;
    if (link.guardianID != currentUserHash || link.patientID.trim().isEmpty) {
      setState(() {
        _statusMessage =
            '\uBCF4\uD638\uC790 \uC5F0\uB3D9 \uBC94\uC704\uC5D0\uC11C\uB9CC \uC54C\uB9BC\uC744 \uC124\uC815\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.';
      });
      return;
    }

    final settingKey = _alertSettingKeyForLink(link);
    setState(() {
      _guardianAlertLoadingKeys = {
        ..._guardianAlertLoadingKeys,
        settingKey,
      };
    });

    final control = SetGuardianAlertSetting(guardianHash: currentUserHash);
    try {
      final setting = await control.updateGuardianAlertSetting(
        patientHash: link.patientID,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _guardianAlertSettings = {
          ..._guardianAlertSettings,
          settingKey: setting,
        };
        _statusMessage = enabled
            ? '\uBCF4\uD638\uC790 \uC54C\uB9BC\uC744 \uCF30\uC2B5\uB2C8\uB2E4.'
            : '\uBCF4\uD638\uC790 \uC54C\uB9BC\uC744 \uB044\uC2B5\uB2C8\uB2E4.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      control.dispose();
      if (mounted) {
        setState(() {
          _guardianAlertLoadingKeys =
              _guardianAlertLoadingKeys.difference({settingKey});
        });
      }
    }
  }

  String get _currentUserHash {
    return PatientHash.normalizePatientHash(_userHashController.text);
  }

  void _applyMedicationScope(List<PatientGuardianLink> links) {
    final scopeCallback = widget.onMedicationScopeSelected;
    if (scopeCallback == null) {
      return;
    }

    final currentUserHash = _currentUserHash;
    for (final link in links) {
      if (link.linked &&
          link.guardianID == currentUserHash &&
          link.patientID.trim().isNotEmpty) {
        scopeCallback(
          patientHash: link.patientID,
          userHash: currentUserHash,
          role: 'guardian',
        );
        return;
      }
    }

    scopeCallback(
      patientHash: currentUserHash,
      role: 'patient',
    );
  }

  Future<void> _showPatientCodeDialog(PatientLinkCode patientCode) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => _PatientCodeDialog(patientCode: patientCode),
    );
  }

  Future<void> _showRegisterPatientDialog() {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => _RegisterPatientDialog(
        userHashController: _userHashController,
        patientCodeController: _patientCodeController,
        onRegisterRequested: _registerPatientCode,
        statusMessageProvider: () => _statusMessage,
      ),
    );
  }
}

class _LinkActionFooter extends StatelessWidget {
  final VoidCallback onGeneratePatientCodeRequested;
  final VoidCallback onRegisterPatientRequested;

  const _LinkActionFooter({
    required this.onGeneratePatientCodeRequested,
    required this.onRegisterPatientRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LinkActionButton(
            title: '환자 코드 생성',
            subtitle: '(환자 휴대폰)',
            onPressed: onGeneratePatientCodeRequested,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LinkActionButton(
            title: '환자 관리 등록',
            subtitle: '(보호자 휴대폰)',
            onPressed: onRegisterPatientRequested,
          ),
        ),
      ],
    );
  }
}

class _LinkActionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const _LinkActionButton({
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(92),
        foregroundColor: const Color(0xFF0A0A0A),
        backgroundColor: Colors.white,
        side: const BorderSide(color: MedBuddyColors.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String statusMessage;
  final bool isLoading;

  const _StatusCard({
    required this.statusMessage,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: MedBuddyColors.primary,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterPatientDialog extends StatefulWidget {
  final TextEditingController userHashController;
  final TextEditingController patientCodeController;
  final Future<bool> Function() onRegisterRequested;
  final String Function() statusMessageProvider;

  const _RegisterPatientDialog({
    required this.userHashController,
    required this.patientCodeController,
    required this.onRegisterRequested,
    required this.statusMessageProvider,
  });

  @override
  State<_RegisterPatientDialog> createState() => _RegisterPatientDialogState();
}

class _RegisterPatientDialogState extends State<_RegisterPatientDialog> {
  bool _isRegistering = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 42),
      child: Container(
        width: 328,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '닫기',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  onPressed:
                      _isRegistering ? null : () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: MedBuddyColors.textMuted,
                    size: 22,
                  ),
                ),
                const Expanded(
                  child: Text(
                    '환자 관리 등록',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF0A0A0A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: widget.userHashController,
              enabled: !_isRegistering,
              decoration: _inputDecoration(
                '보호자 사용자 ID',
                PatientHash.defaultPatientHash,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.patientCodeController,
              enabled: !_isRegistering,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: _inputDecoration('환자 코드', 'ABCD1234'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleRegisterRequested(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _isRegistering ? null : _handleRegisterRequested,
                style: FilledButton.styleFrom(
                  backgroundColor: MedBuddyColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                child: _isRegistering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('등록하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRegisterRequested() async {
    setState(() => _isRegistering = true);
    final success = await widget.onRegisterRequested();
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isRegistering = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.statusMessageProvider())),
    );
  }
}

class _PatientCodeDialog extends StatefulWidget {
  final PatientLinkCode patientCode;

  const _PatientCodeDialog({required this.patientCode});

  @override
  State<_PatientCodeDialog> createState() => _PatientCodeDialogState();
}

class _PatientCodeDialogState extends State<_PatientCodeDialog> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (widget.patientCode.isExpired()) {
        _countdownTimer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 42),
      child: Container(
        width: 328,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 19),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '\uB2EB\uAE30',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF344054),
                    size: 22,
                  ),
                ),
                const Expanded(
                  child: Text(
                    '\uD658\uC790 \uCF54\uB4DC \uC0DD\uC131',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF0A0A0A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
            const SizedBox(height: 20),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.patientCode.code),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '\uCF54\uB4DC\uB97C \uBCF5\uC0AC\uD588\uC2B5\uB2C8\uB2E4.',
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 57,
                  padding: const EdgeInsets.fromLTRB(18, 0, 14, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: MedBuddyColors.outline, width: 2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.patientCode.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1E2939),
                            fontSize: 16,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.copy_outlined,
                        color: Color(0xFF99A1AF),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '(\uCF54\uB4DC\uB97C \uD074\uB9AD\uD558\uBA74 \uBCF5\uC0AC\uB429\uB2C8\uB2E4)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedBuddyColors.textSubtle,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 28),
            _PatientCodeNotice(
              backgroundColor: MedBuddyColors.successSurface,
              foregroundColor: MedBuddyColors.textBody,
              text:
                  '\uD574\uB2F9 \uCF54\uB4DC\uB97C \uBCF4\uD638\uC790 \uD734\uB300\uD3F0\uC5D0\n\uB4F1\uB85D\uD574\uC8FC\uC138\uC694',
            ),
            const SizedBox(height: 15),
            _PatientCodeNotice(
              backgroundColor: Color(0xFFFEF2F2),
              foregroundColor: Color(0xFFE7000B),
              fontWeight: FontWeight.w700,
              text:
                  '\uD574\uB2F9 \uCF54\uB4DC\uB97C \uBCF4\uD638\uC790 \uC678 \uB2E4\uB978 \uC0AC\uB78C\uACFC\n\uACF5\uC720\uD558\uC9C0 \uB9C8\uC138\uC694!',
            ),
            const SizedBox(height: 24),
            Text.rich(
              TextSpan(
                text: '\uB0A8\uC740 \uC2DC\uAC04: ',
                children: [
                  TextSpan(
                    text: _remainingTimeText,
                    style: const TextStyle(
                      color: MedBuddyColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textSubtle,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _remainingTimeText {
    final remaining = widget.patientCode.remaining();
    final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _PatientCodeNotice extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final FontWeight fontWeight;
  final String text;

  const _PatientCodeNotice({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.text,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 78,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: MedBuddyRadii.card,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 14,
          height: 1.45,
          fontWeight: fontWeight,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _LinkListCard extends StatelessWidget {
  final List<PatientGuardianLink> links;
  final String currentUserHash;
  final Map<String, GuardianAlertSetting> guardianAlertSettings;
  final Set<String> guardianAlertLoadingKeys;
  final Future<void> Function(PatientGuardianLink link) onUnlinkRequested;
  final Future<void> Function(PatientGuardianLink link, bool enabled)
      onGuardianAlertChanged;

  const _LinkListCard({
    required this.links,
    required this.currentUserHash,
    required this.guardianAlertSettings,
    required this.guardianAlertLoadingKeys,
    required this.onUnlinkRequested,
    required this.onGuardianAlertChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: links.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final link = links[index];
        return _LinkedUserTile(
          link: link,
          currentUserHash: currentUserHash,
          guardianAlertSetting:
              guardianAlertSettings[_alertSettingKeyForLink(link)],
          isGuardianAlertLoading: guardianAlertLoadingKeys.contains(
            _alertSettingKeyForLink(link),
          ),
          onUnlinkRequested: () => onUnlinkRequested(link),
          onGuardianAlertChanged: (enabled) =>
              onGuardianAlertChanged(link, enabled),
        );
      },
    );
  }
}

class _LinkedUserTile extends StatelessWidget {
  final PatientGuardianLink link;
  final String currentUserHash;
  final GuardianAlertSetting? guardianAlertSetting;
  final bool isGuardianAlertLoading;
  final VoidCallback onUnlinkRequested;
  final Future<void> Function(bool enabled) onGuardianAlertChanged;

  const _LinkedUserTile({
    required this.link,
    required this.currentUserHash,
    required this.guardianAlertSetting,
    required this.isGuardianAlertLoading,
    required this.onUnlinkRequested,
    required this.onGuardianAlertChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '연동 정보',
                  style: TextStyle(
                    color: Color(0xFF0A0A0A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (_canConfigureGuardianAlert)
                IconButton(
                  tooltip: '보호자 알림 설정',
                  onPressed: () => _showGuardianAlertDialog(context),
                  icon: Icon(
                    guardianAlertSetting?.enabled == true
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                    color: guardianAlertSetting?.enabled == true
                        ? MedBuddyColors.primary
                        : MedBuddyColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _LinkedIdentityField(
            label: '사용자 ID',
            value: _displayHash(link.patientID),
          ),
          const SizedBox(height: 10),
          _LinkedIdentityField(
            label: '보호자 ID',
            value: _displayHash(link.guardianID),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onUnlinkRequested,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFB2C36),
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
  }

  bool get _canConfigureGuardianAlert {
    return link.linked &&
        link.guardianID == currentUserHash &&
        link.patientID.trim().isNotEmpty;
  }

  void _showGuardianAlertDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                    const Expanded(
                      child: Text(
                        '보호자 알림 설정',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 12),
                SetGuardianAlertSettingUI(
                  setting: guardianAlertSetting ??
                      GuardianAlertSetting(
                        guardianID: link.guardianID,
                        patientID: link.patientID,
                      ),
                  isLoading: isGuardianAlertLoading,
                  onAlertOptionChanged: (enabled) {
                    Navigator.pop(dialogContext);
                    onGuardianAlertChanged(enabled);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LinkedIdentityField extends StatelessWidget {
  final String label;
  final String value;

  const _LinkedIdentityField({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label :',
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFF0A0A0A),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

String _alertSettingKeyForLink(PatientGuardianLink link) {
  return '${link.guardianID}|${link.patientID}';
}

InputDecoration _inputDecoration(String labelText, String hintText) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: MedBuddyColors.surfaceSubtle,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MedBuddyColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MedBuddyColors.primary, width: 2),
    ),
  );
}

String _displayHash(String value) {
  final displayValue = value.trim();
  if (displayValue.isEmpty) {
    return '\uC815\uBCF4 \uC5C6\uC74C';
  }
  return displayValue;
}
