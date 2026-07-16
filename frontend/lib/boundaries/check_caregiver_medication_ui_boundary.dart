import 'package:flutter/material.dart';

import '../controls/check_caregiver_medication_control.dart';
import '../controls/set_caregiver_notification_control.dart';
import '../entities/caregiver_notification_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'check_medication_detail_ui_boundary.dart';
import 'set_caregiver_notification_ui_boundary.dart';

// Class Name: CheckCaregiverMedicationUI
// Role: Displays read-only medication information for one linked patient.
class CheckCaregiverMedicationUI extends StatefulWidget {
  final String caregiverHash;
  final String patientHash;
  final UserSetting userSetting;
  final CheckCaregiverMedication? control;
  final SetCaregiverNotification? notificationControl;

  const CheckCaregiverMedicationUI({
    super.key,
    required this.caregiverHash,
    required this.patientHash,
    this.userSetting = const UserSetting(),
    this.control,
    this.notificationControl,
  });

  @override
  State<CheckCaregiverMedicationUI> createState() =>
      _CheckCaregiverMedicationUIState();
}

class _CheckCaregiverMedicationUIState
    extends State<CheckCaregiverMedicationUI> {
  late final CheckCaregiverMedication _control;
  late final bool _ownsControl;
  late final SetCaregiverNotification _notificationControl;
  late final bool _ownsNotificationControl;
  CaregiverMedicationInfo? _medicationInfo;
  CaregiverNotification? _notificationSetting;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isNotificationLoading = true;

  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ??
        CheckCaregiverMedication(caregiverHash: widget.caregiverHash);
    _ownsNotificationControl = widget.notificationControl == null;
    _notificationControl = widget.notificationControl ??
        SetCaregiverNotification(caregiverHash: widget.caregiverHash);
    _requestPatientMedicationInfo();
    _requestCaregiverNotificationSetting();
  }

  @override
  void dispose() {
    if (_ownsControl) {
      _control.dispose();
    }
    if (_ownsNotificationControl) {
      _notificationControl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.surface,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.surface,
        foregroundColor: MedBuddyColors.textStrong,
        title: const Text('환자 복약 정보'),
        actions: [
          if (_isNotificationLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: MedBuddyColors.primary,
                ),
              ),
            )
          else
            IconButton(
              tooltip: '보호자 알림 설정',
              onPressed: _showCaregiverNotificationPopup,
              icon: Icon(
                _notificationSetting?.notificationEnabled == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_outlined,
                color: _notificationSetting?.notificationEnabled == true
                    ? MedBuddyColors.primary
                    : MedBuddyColors.textMuted,
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: MedBuddyColors.primary,
        onRefresh: _requestPatientMedicationInfo,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _medicationInfo == null) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }
    if (_errorMessage != null && _medicationInfo == null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 120),
          const Icon(
            Icons.error_outline_rounded,
            color: MedBuddyColors.textMuted,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MedBuddyColors.textMuted),
          ),
        ],
      );
    }

    final info = _medicationInfo;
    if (info == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        _PatientScopeHeader(patientHash: info.patientHash),
        const SizedBox(height: 24),
        _SectionTitle(
          title: '오늘의 복약 일정',
          count: info.todayMedicationScheduleList.length,
        ),
        const SizedBox(height: 12),
        if (info.todayMedicationScheduleList.isEmpty)
          const _EmptySection(message: '오늘 복용할 약이 없습니다.')
        else
          for (final schedule in info.todayMedicationScheduleList)
            _MedicationRow(
              name: schedule.displayName,
              subtitle: schedule.medicationTimeLabel,
              isCompleted: schedule.medicationStatus,
              onTap: () => _openMedicationDetail(
                MedicationDetail.fromMedicationSchedule(schedule),
              ),
            ),
        const SizedBox(height: 28),
        _SectionTitle(
          title: '저장된 복약 정보',
          count: info.savedMedications.length,
        ),
        const SizedBox(height: 12),
        if (info.savedMedications.isEmpty)
          const _EmptySection(message: '저장된 복약 정보가 없습니다.')
        else
          for (final medication in info.savedMedications)
            _MedicationRow(
              name: medication.displayName,
              subtitle: medication.dailyFrequency,
              onTap: () => _openMedicationDetail(medication),
            ),
      ],
    );
  }

  Future<void> _requestPatientMedicationInfo() async {
    if (mounted) {
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
        setState(() => _medicationInfo = info);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _requestCaregiverNotificationSetting({
    bool showError = false,
  }) async {
    if (mounted) {
      setState(() {
        _isNotificationLoading = true;
      });
    }
    try {
      final setting =
          await _notificationControl.requestCaregiverNotificationSetting(
        patientHash: widget.patientHash,
      );
      if (mounted) {
        setState(() => _notificationSetting = setting);
      }
      return true;
    } catch (error) {
      final message = error.toString().replaceFirst('Bad state: ', '');
      if (mounted) {
        if (showError) {
          _showMessage(message);
        }
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isNotificationLoading = false);
      }
    }
  }

  Future<void> _showCaregiverNotificationPopup() async {
    if (_notificationSetting == null) {
      final loaded = await _requestCaregiverNotificationSetting(
        showError: true,
      );
      if (!loaded || !mounted) {
        return;
      }
    }

    final setting = _notificationSetting;
    if (setting == null || !mounted) {
      return;
    }
    final enabled = await SetCaregiverNotificationUI.showNotificationPopup(
      context,
      setting: setting,
      language: widget.userSetting.language,
    );
    if (enabled == null || enabled == setting.notificationEnabled) {
      return;
    }
    await _saveCaregiverNotificationSetting(enabled);
  }

  Future<void> _saveCaregiverNotificationSetting(bool enabled) async {
    setState(() {
      _isNotificationLoading = true;
    });
    try {
      final setting =
          await _notificationControl.saveCaregiverNotificationSetting(
        patientHash: widget.patientHash,
        enabled: enabled,
      );
      if (mounted) {
        setState(() => _notificationSetting = setting);
      }
    } catch (error) {
      final message = error.toString().replaceFirst('Bad state: ', '');
      if (mounted) {
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isNotificationLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMedicationDetail(MedicationDetail medication) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: medication,
          userSetting: widget.userSetting,
        ),
      ),
    );
  }
}

class _PatientScopeHeader extends StatelessWidget {
  final String patientHash;

  const _PatientScopeHeader({required this.patientHash});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.mint, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: MedBuddyColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '환자 ID: $patientHash',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.visibility_outlined,
              color: MedBuddyColors.textMuted),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$title ($count)',
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MedicationRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isCompleted;
  final VoidCallback onTap;

  const _MedicationRow({
    required this.name,
    required this.subtitle,
    this.isCompleted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.trim().isEmpty ? null : Text(subtitle),
        trailing: Icon(
          isCompleted ? Icons.check_circle : Icons.chevron_right,
          color:
              isCompleted ? MedBuddyColors.primary : MedBuddyColors.textMuted,
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;

  const _EmptySection({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: MedBuddyColors.textMuted),
      ),
    );
  }
}
