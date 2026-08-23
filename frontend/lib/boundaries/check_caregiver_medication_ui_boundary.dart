// 파일명: check_caregiver_medication_ui_boundary.dart
// 역할: 보호자가 연동 환자의 시간대별 복약 상태와 알림을 확인하는 화면을 제공한다.

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

class CheckCaregiverMedicationUI extends StatefulWidget {
  final String caregiverHash;
  final String patientHash;
  final String? patientLabel;
  final UserSetting userSetting;
  final CheckCaregiverMedication? control;
  final SetCaregiverNotification? notificationControl;

  const CheckCaregiverMedicationUI({
    super.key,
    required this.caregiverHash,
    required this.patientHash,
    this.patientLabel,
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

  bool get _isEnglish {
    return widget.userSetting.language.trim().toLowerCase().startsWith('en');
  }

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
      (_) => unawaited(_refreshCaregiverData()),
    );
  }

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
            medications: schedules
                .where((schedule) => schedule.slotKeys.contains(slot.key))
                .toList(growable: false),
            notificationSetting: _notificationSettings[slot.key],
            isNotificationLoading:
                _isNotificationLoading ||
                _notificationSavingSlotKey == slot.key,
            onNotification: () => _showCaregiverNotificationPopup(slot),
            onMedicationTap: _openMedicationDetail,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // 함수이름: _refreshCaregiverData
  // 함수역할:
  // - 선택 환자의 복약 일정과 보호자 알림 설정을 같은 주기로 갱신한다.
  // 반환값:
  // - 없음
  Future<void> _refreshCaregiverData() async {
    await Future.wait([
      _requestPatientMedicationInfo(silent: true),
      _requestCaregiverNotificationSettings(silent: true),
    ]);
  }

  // 함수이름: _loadPatientLabel
  // 함수역할:
  // - 현재 보호자가 지정한 환자 표시 이름을 로컬 저장소에서 읽어 헤더에 반영한다.
  // 반환값:
  // - 없음
  Future<void> _loadPatientLabel() async {
    final label = await _localStateControl.loadLabel(
      caregiverHash: widget.caregiverHash,
      patientHash: widget.patientHash,
    );
    if (!mounted || label == _patientLabel) {
      return;
    }
    setState(() => _patientLabel = label);
  }

  Future<void> _requestPatientMedicationInfo({bool silent = false}) async {
    if (_isRefreshInFlight) {
      return;
    }
    _isRefreshInFlight = true;
    if (mounted && !silent) {
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
        setState(() {
          _medicationInfo = info;
          _errorMessage = null;
          _lastSynchronizedAt = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) {
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _requestCaregiverNotificationSettings({
    bool showError = false,
    bool silent = false,
  }) async {
    if (_isNotificationRefreshInFlight) {
      return false;
    }
    _isNotificationRefreshInFlight = true;
    if (mounted && !silent) {
      setState(() => _isNotificationLoading = true);
    }
    try {
      final settings = await _notificationControl
          .requestCaregiverNotificationSettings(
            patientHash: widget.patientHash,
          );
      if (mounted) {
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
        setState(() => _isNotificationLoading = false);
      }
    }
  }

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

  Future<void> _saveCaregiverNotificationSetting(
    _CaregiverScheduleSlot slot,
    CaregiverNotification selectedSetting,
  ) async {
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
        setState(() => _notificationSavingSlotKey = null);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMedicationDetail(MedicationSchedule schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: MedicationDetail.fromMedicationSchedule(schedule),
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

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
// 역할: 보호자가 보고 있는 복약 상태의 동기화 시점과 지연 여부를 명확히 안내한다.
class _CaregiverSynchronizationBanner extends StatelessWidget {
  final bool isEnglish;
  final DateTime? lastSynchronizedAt;
  final bool hasSynchronizationError;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _CaregiverSynchronizationBanner({
    required this.isEnglish,
    required this.lastSynchronizedAt,
    required this.hasSynchronizationError,
    required this.isRefreshing,
    required this.onRefresh,
  });

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

class _CaregiverScheduleHeader extends StatelessWidget {
  final bool isEnglish;
  final String patientLabel;
  final int completedCount;
  final int totalCount;
  final VoidCallback onBack;

  const _CaregiverScheduleHeader({
    required this.isEnglish,
    required this.patientLabel,
    required this.completedCount,
    required this.totalCount,
    required this.onBack,
  });

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

class _CaregiverTimeSlotCard extends StatelessWidget {
  final _CaregiverScheduleSlot slot;
  final bool isEnglish;
  final List<MedicationSchedule> medications;
  final CaregiverNotification? notificationSetting;
  final bool isNotificationLoading;
  final VoidCallback onNotification;
  final ValueChanged<MedicationSchedule> onMedicationTap;

  const _CaregiverTimeSlotCard({
    required this.slot,
    required this.isEnglish,
    required this.medications,
    required this.notificationSetting,
    required this.isNotificationLoading,
    required this.onNotification,
    required this.onMedicationTap,
  });

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
                        slot.timeLabel,
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

class _CaregiverMedicationRow extends StatelessWidget {
  final MedicationSchedule schedule;
  final String slotKey;
  final bool isEnglish;
  final VoidCallback onTap;

  const _CaregiverMedicationRow({
    required this.schedule,
    required this.slotKey,
    required this.isEnglish,
    required this.onTap,
  });

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

  static String _dosageLabel(MedicationSchedule schedule, bool isEnglish) {
    return schedule.dosageLabelForLanguage(isEnglish ? 'en' : 'ko');
  }
}

class _MedicationThumbnail extends StatelessWidget {
  final MedicationSchedule schedule;

  const _MedicationThumbnail({required this.schedule});

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
              errorBuilder: (_, _, _) => const Icon(
                Icons.image_not_supported_outlined,
                color: MedBuddyColors.textLight,
              ),
            ),
    );
  }
}

class _CaregiverScheduleSlot {
  final String key;
  final int hour;
  final Color color;
  final IconData icon;

  const _CaregiverScheduleSlot({
    required this.key,
    required this.hour,
    required this.color,
    required this.icon,
  });

  String get timeLabel => '${hour.toString().padLeft(2, '0')}:00';

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
