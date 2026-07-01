import 'package:flutter/material.dart';

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
  String? _patientCode;
  String _statusMessage =
      '\uD604\uC7AC \uC0AC\uC6A9\uC790 \uD574\uC2DC\uB85C \uC5F0\uB3D9 \uC0C1\uD0DC\uB97C \uD655\uC778\uD569\uB2C8\uB2E4.';
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
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _LinkHeader(onBackRequested: () => Navigator.pop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                children: [
                  _StatusCard(
                    statusMessage: _statusMessage,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 16),
                  _CurrentUserCard(
                    controller: _userHashController,
                    onRefreshRequested: _refreshLinks,
                    onGeneratePatientCodeRequested: _requestPatientCode,
                  ),
                  if (_patientCode != null) ...[
                    const SizedBox(height: 16),
                    _PatientCodeCard(patientCode: _patientCode!),
                  ],
                  const SizedBox(height: 16),
                  _RegisterPatientCard(
                    controller: _patientCodeController,
                    onRegisterRequested: _registerPatientCode,
                  ),
                  const SizedBox(height: 16),
                  _LinkListCard(
                    links: _links,
                    currentUserHash: _currentUserHash,
                    guardianAlertSettings: _guardianAlertSettings,
                    guardianAlertLoadingKeys: _guardianAlertLoadingKeys,
                    onUnlinkRequested: _requestUnlink,
                    onGuardianAlertChanged: _updateGuardianAlertSetting,
                  ),
                ],
              ),
            ),
          ],
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
              ? '\uC544\uC9C1 \uC5F0\uB3D9\uB41C \uD658\uC790/\uBCF4\uD638\uC790\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
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
    await _runLinkAction(() async {
      final control = _buildControl();
      try {
        final patientCode = await control.requestPatientCode();
        if (!mounted) {
          return;
        }
        setState(() {
          _patientCode = patientCode;
          _statusMessage =
              '\uBCF4\uD638\uC790\uC5D0\uAC8C \uACF5\uC720\uD560 \uC5F0\uB3D9 \uCF54\uB4DC\uB97C \uC0DD\uC131\uD588\uC2B5\uB2C8\uB2E4.';
        });
      } finally {
        control.dispose();
      }
    });
  }

  Future<void> _registerPatientCode() async {
    final patientCode = _patientCodeController.text.trim();
    if (patientCode.isEmpty) {
      setState(() {
        _statusMessage =
            '\uB4F1\uB85D\uD560 \uD658\uC790 \uC5F0\uB3D9 \uCF54\uB4DC\uB97C \uC785\uB825\uD574 \uC8FC\uC138\uC694.';
      });
      return;
    }

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
        });
        _applyMedicationScope(links);
        await _requestGuardianAlertSettings(links);
      } finally {
        control.dispose();
      }
    });
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
          )..remove(_alertSettingKey(link));
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

    final loadingKeys = guardianLinks.map(_alertSettingKey).toSet();
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
          nextSettings[_alertSettingKey(link)] =
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

    final settingKey = _alertSettingKey(link);
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

  String _alertSettingKey(PatientGuardianLink link) {
    return '${link.guardianID}|${link.patientID}';
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
}

class _LinkHeader extends StatelessWidget {
  final VoidCallback onBackRequested;

  const _LinkHeader({required this.onBackRequested});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const Expanded(
            child: Text(
              '\uD658\uC790/\uBCF4\uD638\uC790 \uC5F0\uB3D9',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFA4F4CF), width: 2),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.mint,
              shape: BoxShape.circle,
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      color: MedBuddyColors.primary,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(
                    Icons.link_outlined,
                    color: MedBuddyColors.primary,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusMessage,
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

class _CurrentUserCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRefreshRequested;
  final VoidCallback onGeneratePatientCodeRequested;

  const _CurrentUserCard({
    required this.controller,
    required this.onRefreshRequested,
    required this.onGeneratePatientCodeRequested,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.person_outline,
      title: '\uD604\uC7AC \uC0AC\uC6A9\uC790',
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: _inputDecoration(
              '\uC0AC\uC6A9\uC790 \uD574\uC2DC',
              PatientHash.defaultPatientHash,
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefreshRequested,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('\uC0C8\uB85C\uACE0\uCE68'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onGeneratePatientCodeRequested,
                  icon: const Icon(Icons.qr_code_2_outlined),
                  label: const Text('\uCF54\uB4DC \uC0DD\uC131'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatientCodeCard extends StatelessWidget {
  final String patientCode;

  const _PatientCodeCard({required this.patientCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.mint, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '\uACF5\uC720 \uCF54\uB4DC',
            style: TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            patientCode,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 30,
              letterSpacing: 0,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '\uBCF4\uD638\uC790\uAC00 \uC774 \uCF54\uB4DC\uB97C \uB4F1\uB85D\uD558\uBA74 \uD658\uC790 \uBCF5\uC57D \uC815\uBCF4\uB97C \uD655\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterPatientCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRegisterRequested;

  const _RegisterPatientCard({
    required this.controller,
    required this.onRegisterRequested,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.group_add_outlined,
      title: '\uD658\uC790 \uCF54\uB4DC \uB4F1\uB85D',
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: _inputDecoration(
              '\uC5F0\uB3D9 \uCF54\uB4DC',
              'ABCD1234',
            ),
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRegisterRequested,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('\uD658\uC790 \uC5F0\uB3D9'),
            ),
          ),
        ],
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
    return _SectionCard(
      icon: Icons.supervisor_account_outlined,
      title: '\uC5F0\uB3D9 \uBAA9\uB85D',
      child: links.isEmpty
          ? const _EmptyLinkList()
          : Column(
              children: [
                for (final link in links) ...[
                  _LinkedUserTile(
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
                  ),
                  if (link != links.last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _LinkedUserTile extends StatelessWidget {
  final PatientGuardianLink link;
  final String currentUserHash;
  final GuardianAlertSetting? guardianAlertSetting;
  final bool isGuardianAlertLoading;
  final VoidCallback onUnlinkRequested;
  final ValueChanged<bool> onGuardianAlertChanged;

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
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: link.linked
                      ? MedBuddyColors.primary
                      : MedBuddyColors.textLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  link.linked ? Icons.link : Icons.link_off_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayHash(link.patientID),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\uBCF4\uD638\uC790 ${_displayHash(link.guardianID)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Unlink',
                icon: const Icon(
                  Icons.delete_outline,
                  color: MedBuddyColors.primary,
                ),
                onPressed: onUnlinkRequested,
              ),
            ],
          ),
          if (_canConfigureGuardianAlert) ...[
            SetGuardianAlertSettingUI(
              setting: guardianAlertSetting ??
                  GuardianAlertSetting(
                    guardianID: link.guardianID,
                    patientID: link.patientID,
                  ),
              isLoading: isGuardianAlertLoading,
              onAlertOptionChanged: onGuardianAlertChanged,
            ),
          ],
        ],
      ),
    );
  }

  bool get _canConfigureGuardianAlert {
    return link.linked &&
        link.guardianID == currentUserHash &&
        link.patientID.trim().isNotEmpty;
  }
}

class _EmptyLinkList extends StatelessWidget {
  const _EmptyLinkList();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(
            Icons.link_off_outlined,
            color: MedBuddyColors.textLight,
            size: 42,
          ),
          SizedBox(height: 10),
          Text(
            '\uC5F0\uB3D9\uB41C \uD56D\uBAA9\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String labelText, String hintText) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: const Color(0xFFFAFAFA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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
