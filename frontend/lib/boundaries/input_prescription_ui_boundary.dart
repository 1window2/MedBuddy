import 'package:flutter/material.dart';

import 'check_today_medication_info_ui_boundary.dart';
import 'medication_capture_options_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: input_prescription_ui_boundary.dart
// 역할: MedBuddy 홈 화면과 처방전 입력 진입점을 구성한다.

// 클래스명: InputPrescriptionUI
// 역할: 오늘의 복약 일정, 처방전 촬영, 저장된 복약 정보, 환자/보호자 연동으로 이동하는 홈 화면이다.
// 주요 책임:
// - 사용자 설정에 맞춘 홈 화면 문구와 글자 크기를 보여준다.
// - 카메라/갤러리 처방전 입력 방식을 선택할 수 있게 한다.
// - OCR 진행 중에는 입력 화면 대신 진행 상태를 보여준다.
class InputPrescriptionUI extends StatelessWidget {
  final String statusMessage;
  final UserSetting userSetting;
  final List<MedicationSchedule> todayMedicationScheduleList;
  final Map<String, MedicationAlarm> medicationReminderSettings;
  final int todayMedicationCompletedCount;
  final int todayMedicationTotalCount;
  final bool isTodayScheduleLoading;
  final VoidCallback? onPrescriptionScanRequested;
  final VoidCallback? onPrescriptionGalleryRequested;
  final VoidCallback? onPillIdentificationRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onPatientCaregiverLinkRequested;
  final VoidCallback? onUserSettingRequested;
  final bool isAnalyzing;

  const InputPrescriptionUI({
    super.key,
    required this.statusMessage,
    required this.userSetting,
    this.todayMedicationScheduleList = const [],
    this.medicationReminderSettings = const {},
    this.todayMedicationCompletedCount = 0,
    this.todayMedicationTotalCount = 0,
    this.isTodayScheduleLoading = false,
    required this.onPrescriptionScanRequested,
    required this.onPrescriptionGalleryRequested,
    required this.onPillIdentificationRequested,
    required this.onTodayScheduleRequested,
    required this.onSavedMedicationRequested,
    required this.onPatientCaregiverLinkRequested,
    required this.onUserSettingRequested,
  }) : isAnalyzing = false;

  const InputPrescriptionUI.analyzing({super.key, required this.statusMessage})
    : userSetting = const UserSetting(),
      todayMedicationScheduleList = const [],
      medicationReminderSettings = const {},
      todayMedicationCompletedCount = 0,
      todayMedicationTotalCount = 0,
      isTodayScheduleLoading = false,
      onPrescriptionScanRequested = null,
      onPrescriptionGalleryRequested = null,
      onPillIdentificationRequested = null,
      onTodayScheduleRequested = null,
      onSavedMedicationRequested = null,
      onPatientCaregiverLinkRequested = null,
      onUserSettingRequested = null,
      isAnalyzing = true;

  @override
  Widget build(BuildContext context) {
    final text = _HomeText(userSetting.language);

    if (isAnalyzing) {
      return _buildAnalyzingScreen(text);
    }

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _HomeHeader(onSettingPressed: onUserSettingRequested),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: MedBuddySpacing.contentMaxWidth,
                    ),
                    child: Column(
                      children: [
                        _HomeEncouragementPanel(
                          userSetting: userSetting,
                          schedules: todayMedicationScheduleList,
                          reminderSettings: medicationReminderSettings,
                          completedCount: todayMedicationCompletedCount,
                          totalCount: todayMedicationTotalCount,
                          isLoading: isTodayScheduleLoading,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final textScale =
                                MediaQuery.textScalerOf(context).scale(16) / 16;
                            final useGrid =
                                MediaQuery.sizeOf(context).width >= 350;
                            final useLargeTextGridLayout = textScale > 1.1;
                            final homeActions = <Widget>[
                              CheckTodayMedicationInfoUI(
                                title: text.todaySchedule,
                                noMedicationLabel: text.noMedication,
                                userSetting: userSetting,
                                schedules: todayMedicationScheduleList,
                                reminderSettings: medicationReminderSettings,
                                completedCount: todayMedicationCompletedCount,
                                totalCount: todayMedicationTotalCount,
                                isLoading: isTodayScheduleLoading,
                                onTap: onTodayScheduleRequested,
                                compact: useGrid,
                                largeTextGridLayout: useLargeTextGridLayout,
                                largeGridTitle: text.largeTodaySchedule,
                              ),
                              _HomeActionCard(
                                cardKey: const ValueKey('homeCaptureCard'),
                                icon: Icons.photo_camera_outlined,
                                title: text.scanPrescription,
                                subtitle: text.scanPrescriptionSubtitle,
                                filled: true,
                                compact: useGrid,
                                largeTextGridLayout: useLargeTextGridLayout,
                                largeGridTitle: text.largeScanPrescription,
                                userSetting: userSetting,
                                onTap: () => _showAnalysisTaskOptions(context),
                              ),
                              _HomeActionCard(
                                cardKey: const ValueKey(
                                  'homeSavedMedicationCard',
                                ),
                                icon: Icons.medication_outlined,
                                title: text.savedMedication,
                                subtitle: text.savedMedicationSubtitle,
                                filled: false,
                                compact: useGrid,
                                largeTextGridLayout: useLargeTextGridLayout,
                                largeGridTitle: text.largeSavedMedication,
                                userSetting: userSetting,
                                onTap: onSavedMedicationRequested,
                              ),
                              _HomeActionCard(
                                cardKey: const ValueKey(
                                  'homePatientCaregiverLinkCard',
                                ),
                                icon: Icons.people_alt_outlined,
                                title: text.patientCaregiverLink,
                                subtitle: text.patientCaregiverLinkSubtitle,
                                filled: false,
                                compact: useGrid,
                                largeTextGridLayout: useLargeTextGridLayout,
                                largeGridTitle: text.largePatientCaregiverLink,
                                userSetting: userSetting,
                                onTap: onPatientCaregiverLinkRequested,
                              ),
                            ];

                            if (!useGrid) {
                              return Column(
                                children: [
                                  for (
                                    int index = 0;
                                    index < homeActions.length;
                                    index++
                                  ) ...[
                                    homeActions[index],
                                    if (index != homeActions.length - 1)
                                      const SizedBox(height: 14),
                                  ],
                                ],
                              );
                            }

                            return Column(
                              children: [
                                GridView.count(
                                  crossAxisCount: 2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 1,
                                  children: homeActions,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _showAnalysisTaskOptions
  // 함수역할:
  // - 공통 선택 화면에서 처방전 분석 또는 낱알약 식별 작업을 선택하게 한다.
  // - 처방전 분석을 선택하면 카메라와 갤러리 중 이미지 출처를 추가로 선택하게 한다.
  // 매개변수:
  // - context: 선택 화면 표시와 화면 활성 상태 확인에 사용할 BuildContext
  // 반환값:
  // - 없음
  Future<void> _showAnalysisTaskOptions(BuildContext context) async {
    final task = await showMedicationCaptureTaskOptions(
      context: context,
      userSetting: userSetting,
    );

    if (!context.mounted || task == null) {
      return;
    }
    if (task == MedicationCaptureTask.pill) {
      onPillIdentificationRequested?.call();
      return;
    }
    final source = await showPrescriptionImageSourceOptions(
      context: context,
      userSetting: userSetting,
    );
    if (!context.mounted || source == null) {
      return;
    }
    if (source == PrescriptionImageSource.camera) {
      onPrescriptionScanRequested?.call();
      return;
    }
    onPrescriptionGalleryRequested?.call();
  }

  // 함수명: _buildAnalyzingScreen
  // 함수역할:
  // - 처방전 이미지가 선택된 뒤 OCR 요청이 진행되는 동안 보여줄 화면을 만든다.
  // 매개변수:
  // - text: 현재 언어에 맞는 홈 화면 문구 묶음
  // 반환값:
  // - 분석 진행 상태 Widget
  Widget _buildAnalyzingScreen(_HomeText text) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MedBuddyColors.analysisBackground, Colors.white],
          ),
        ),
        child: Center(
          child: Container(
            width: 328,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: MedBuddyColors.outline, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 22,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    color: MedBuddyColors.primary,
                    strokeWidth: 7,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  text.analyzingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textSubtle,
                    fontSize: 15,
                    height: 1.45,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 26),
                ClipRRect(
                  borderRadius: MedBuddyRadii.pill,
                  child: const LinearProgressIndicator(
                    minHeight: 10,
                    color: MedBuddyColors.primary,
                    backgroundColor: MedBuddyColors.divider,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback? onSettingPressed;

  const _HomeHeader({required this.onSettingPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: MedBuddyColors.surface,
        border: Border(bottom: BorderSide(color: MedBuddyColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        28,
        MediaQuery.of(context).padding.top + 16,
        28,
        16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MedBuddySpacing.contentMaxWidth,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MedBuddy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '건강한 복약 관리 도우미',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: MedBuddyColors.textSubtle,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Material(
                color: MedBuddyColors.mint,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSettingPressed,
                  child: const SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(
                      Icons.settings_outlined,
                      color: MedBuddyColors.primaryDark,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final Key? cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final bool compact;
  final bool largeTextGridLayout;
  final String? largeGridTitle;
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _HomeActionCard({
    this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    this.compact = false,
    this.largeTextGridLayout = false,
    this.largeGridTitle,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? MedBuddyColors.primary
        : icon == Icons.medication_outlined
        ? MedBuddyColors.lavenderSurface
        : MedBuddyColors.mint;
    final foreground = filled ? Colors.white : MedBuddyColors.textStrong;
    final secondary = filled
        ? const Color(0xFFFFE8E6)
        : MedBuddyColors.textMuted;
    final scale = userSetting.contentTextScale;
    final displayedTitle = largeTextGridLayout
        ? largeGridTitle ?? title
        : title;

    return Material(
      color: background,
      borderRadius: MedBuddyRadii.largeCard,
      elevation: 0,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTap,
        child: Container(
          key: cardKey,
          width: double.infinity,
          constraints: compact ? null : const BoxConstraints(minHeight: 94),
          padding: compact
              ? const EdgeInsets.all(10)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            boxShadow: MedBuddyShadows.soft,
            border: Border.all(
              color: filled
                  ? MedBuddyColors.primary
                  : MedBuddyColors.cardBorder,
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: filled
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icon, color: foreground, size: 40),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      displayedTitle,
                      maxLines: largeTextGridLayout ? 2 : 2,
                      overflow: largeTextGridLayout
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      textScaler: largeTextGridLayout
                          ? TextScaler.linear(userSetting.preferredTextScale)
                          : null,
                      style: TextStyle(
                        color: foreground,
                        fontSize: largeTextGridLayout ? 16 : 17 * scale,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!largeTextGridLayout) ...[
                      const SizedBox(height: 2),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 10 * scale,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: filled
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: foreground, size: 25),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 17 * scale,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12 * scale,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: filled ? Colors.white : MedBuddyColors.textMuted,
                      size: 17,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HomeText {
  final String language;

  const _HomeText(this.language);

  bool get isEnglish => language == 'en';

  String get todaySchedule => isEnglish ? 'Today\'s Medication' : '오늘의 복약 일정';
  String get largeTodaySchedule =>
      isEnglish ? 'Today\'s\nMedication' : '오늘의\n복약 일정';
  String get noMedication => isEnglish
      ? 'No medicine registered\nScan a prescription'
      : '등록된 약이 없습니다\n처방전을 촬영해주세요';
  String get scanPrescription =>
      isEnglish ? 'Analyze with Camera' : '약 정보 촬영하기';
  String get largeScanPrescription =>
      isEnglish ? 'Analyze\nwith Camera' : '약 정보\n촬영하기';
  String get scanPrescriptionSubtitle => isEnglish
      ? 'Choose a prescription or a loose pill'
      : '처방전 또는 낱알약을 촬영해 분석하세요';
  String get savedMedication => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  String get largeSavedMedication =>
      isEnglish ? 'Saved\nMedication' : '지정된\n복약 정보';
  String get savedMedicationSubtitle =>
      isEnglish ? 'Check saved medication info' : '저장해 둔 약 정보를 확인하세요';
  String get patientCaregiverLink =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  String get largePatientCaregiverLink =>
      isEnglish ? 'Patient/\nCaregiver Link' : '환자/보호자\n연동';
  String get patientCaregiverLinkSubtitle => isEnglish
      ? 'Connect patient and caregiver medication schedules'
      : '환자와 보호자의 복약 일정을 연결';
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}

// 대시보드 첫 줄을 가로지르는 복약 현황 정보 영역이다.
class _HomeEncouragementPanel extends StatelessWidget {
  final UserSetting userSetting;
  final List<MedicationSchedule> schedules;
  final Map<String, MedicationAlarm> reminderSettings;
  final int completedCount;
  final int totalCount;
  final bool isLoading;

  const _HomeEncouragementPanel({
    required this.userSetting,
    required this.schedules,
    required this.reminderSettings,
    required this.completedCount,
    required this.totalCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isEnglish = userSetting.language.trim().toLowerCase().startsWith(
      'en',
    );
    final dashboard = _HomeDashboardSummary.from(
      schedules: schedules,
      reminderSettings: reminderSettings,
      completedCount: completedCount,
      totalCount: totalCount,
      isLoading: isLoading,
      isEnglish: isEnglish,
    );
    final useStackedProgressLabel =
        MediaQuery.textScalerOf(context).scale(16) / 16 > 1.1;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.cardBorder),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MedBuddyColors.mint,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: MedBuddyColors.primaryDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dashboard.statusMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (useStackedProgressLabel)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnglish ? 'Today\'s progress' : '오늘의 복약 진행률',
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dashboard.progressLabel,
                  style: const TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Text(
                  isEnglish ? 'Today\'s progress' : '오늘의 복약 진행률',
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  dashboard.progressLabel,
                  style: const TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: MedBuddyRadii.pill,
            child: LinearProgressIndicator(
              value: dashboard.progress,
              minHeight: 9,
              color: MedBuddyColors.primary,
              backgroundColor: MedBuddyColors.mint,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MedBuddyColors.surfaceSubtle,
              borderRadius: MedBuddyRadii.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: dashboard.hasNextMedication
                        ? MedBuddyColors.mint
                        : MedBuddyColors.lavenderSurface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    dashboard.hasNextMedication
                        ? Icons.alarm_outlined
                        : Icons.event_available_outlined,
                    color: MedBuddyColors.primaryDark,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dashboard.nextMedicationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dashboard.nextMedicationGuide,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MedBuddyColors.textMuted,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _HomeDashboardSummary {
  static const _slotOrder = ['morning', 'lunch', 'evening', 'bedtime'];

  final double progress;
  final String progressLabel;
  final String statusMessage;
  final bool hasNextMedication;
  final String nextMedicationLabel;
  final String nextMedicationGuide;

  const _HomeDashboardSummary({
    required this.progress,
    required this.progressLabel,
    required this.statusMessage,
    required this.hasNextMedication,
    required this.nextMedicationLabel,
    required this.nextMedicationGuide,
  });

  factory _HomeDashboardSummary.from({
    required List<MedicationSchedule> schedules,
    required Map<String, MedicationAlarm> reminderSettings,
    required int completedCount,
    required int totalCount,
    required bool isLoading,
    required bool isEnglish,
  }) {
    if (isLoading) {
      return _HomeDashboardSummary(
        progress: 0,
        progressLabel: '-/-',
        statusMessage: isEnglish
            ? 'Preparing your medication plan'
            : '복약 일정을 준비하고 있어요',
        hasNextMedication: false,
        nextMedicationLabel: isEnglish ? 'Next medication' : '다음 복약',
        nextMedicationGuide: isEnglish
            ? 'Please wait a moment.'
            : '잠시만 기다려주세요.',
      );
    }

    final displayTotal = totalCount > 0 ? totalCount : schedules.length;
    final safeCompleted = displayTotal == 0
        ? 0
        : completedCount.clamp(0, displayTotal);
    final progress = displayTotal == 0 ? 0.0 : safeCompleted / displayTotal;
    final progressLabel = displayTotal == 0
        ? '-/-'
        : '$safeCompleted/$displayTotal';
    final now = DateTime.now();
    final pendingSlots = <_DashboardPendingSlot>[];

    for (final slotKey in _slotOrder) {
      final pendingSchedules = schedules
          .where(
            (schedule) =>
                schedule.slotKeys.contains(slotKey) &&
                !schedule.isSlotCompleted(slotKey),
          )
          .toList(growable: false);
      if (pendingSchedules.isEmpty) {
        continue;
      }
      final alarm =
          reminderSettings[slotKey] ?? MedicationAlarm.defaults(slotKey);
      pendingSlots.add(
        _DashboardPendingSlot(
          slotKey: slotKey,
          scheduledAt: DateTime(
            now.year,
            now.month,
            now.day,
            alarm.hour,
            alarm.minute,
          ),
          medication: pendingSchedules.first,
        ),
      );
    }

    if (pendingSlots.isEmpty) {
      return _HomeDashboardSummary(
        progress: progress,
        progressLabel: progressLabel,
        statusMessage: displayTotal == 0
            ? (isEnglish
                  ? 'Start your medication plan with ease'
                  : '오늘도 건강한 복약을 시작해보세요')
            : (isEnglish
                  ? 'You have completed today\'s medication'
                  : '오늘의 복약을 모두 완료했어요'),
        hasNextMedication: false,
        nextMedicationLabel: isEnglish
            ? 'No upcoming medication'
            : '다음 복약 일정이 없어요',
        nextMedicationGuide: isEnglish
            ? 'Take time to rest and recharge.'
            : '남은 시간도 편안하게 보내세요.',
      );
    }

    final nextSlot = pendingSlots.firstWhere(
      (slot) => !slot.scheduledAt.isBefore(now),
      orElse: () => pendingSlots.first,
    );
    final isPastDue = nextSlot.scheduledAt.isBefore(now);
    final timeLabel =
        '${nextSlot.scheduledAt.hour.toString().padLeft(2, '0')}:${nextSlot.scheduledAt.minute.toString().padLeft(2, '0')}';
    final medicationName = nextSlot.medication.displayNameForLanguage(
      isEnglish ? 'en' : 'ko',
    );

    return _HomeDashboardSummary(
      progress: progress,
      progressLabel: progressLabel,
      statusMessage: displayTotal == 0
          ? (isEnglish
                ? 'Your medication guide is ready'
                : '오늘도 복약을 차분히 시작해보세요')
          : (isEnglish
                ? 'You are keeping up with your medication'
                : '오늘도 복약을 꾸준히 이어가고 있어요'),
      hasNextMedication: true,
      nextMedicationLabel: isPastDue
          ? (isEnglish ? 'Missed dose check' : '미복용 확인')
          : (isEnglish ? 'Next medication' : '다음 복약 알림'),
      nextMedicationGuide: isEnglish
          ? '${_slotLabel(nextSlot.slotKey)} $timeLabel · $medicationName\n${isPastDue ? 'Please take it as soon as you can.' : 'Take it on time.'}'
          : '${_slotLabel(nextSlot.slotKey)} $timeLabel · $medicationName\n${isPastDue ? '늦지 않게 복용하세요.' : '시간에 맞춰 챙겨드세요.'}',
    );
  }

  static String _slotLabel(String slotKey) {
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => slotKey,
    };
  }
}

class _DashboardPendingSlot {
  final String slotKey;
  final DateTime scheduledAt;
  final MedicationSchedule medication;

  const _DashboardPendingSlot({
    required this.slotKey,
    required this.scheduledAt,
    required this.medication,
  });
}
