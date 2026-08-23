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
            _HomeHeader(
              subtitle: text.brandSubtitle,
              onSettingPressed: onUserSettingRequested,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(42, 10, 42, 24),
                child: Column(
                  children: [
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
                    ),
                    const SizedBox(height: 20),
                    _HomeActionCard(
                      cardKey: const ValueKey('homeCaptureCard'),
                      icon: Icons.photo_camera_outlined,
                      title: text.scanPrescription,
                      subtitle: text.scanPrescriptionSubtitle,
                      filled: true,
                      userSetting: userSetting,
                      onTap: () => _showAnalysisTaskOptions(context),
                    ),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      cardKey: const ValueKey('homeSavedMedicationCard'),
                      icon: Icons.medication_outlined,
                      title: text.savedMedication,
                      subtitle: text.savedMedicationSubtitle,
                      filled: false,
                      userSetting: userSetting,
                      onTap: onSavedMedicationRequested,
                    ),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      cardKey: const ValueKey('homePatientCaregiverLinkCard'),
                      icon: Icons.people_alt_outlined,
                      title: text.patientCaregiverLink,
                      subtitle: text.patientCaregiverLinkSubtitle,
                      filled: false,
                      userSetting: userSetting,
                      onTap: onPatientCaregiverLinkRequested,
                    ),
                  ],
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
  final String subtitle;
  final VoidCallback? onSettingPressed;

  const _HomeHeader({
    required this.subtitle,
    required this.onSettingPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(48, 44, 34, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'MedBuddy',
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Material(
            color: MedBuddyColors.primaryDark,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSettingPressed,
              child: const SizedBox(
                width: 55,
                height: 55,
                child: Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 29,
                ),
              ),
            ),
          ),
        ],
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
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _HomeActionCard({
    this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? MedBuddyColors.primary : Colors.white;
    final foreground = filled ? Colors.white : MedBuddyColors.primaryDark;
    final secondary = filled ? MedBuddyColors.mint : MedBuddyColors.primary;
    final scale = userSetting.contentTextScale;

    return Material(
      color: background,
      borderRadius: MedBuddyRadii.card,
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          key: cardKey,
          width: double.infinity,
          constraints: BoxConstraints(minHeight: filled ? 176 : 182),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: filled
                ? null
                : Border.all(color: MedBuddyColors.mint, width: 2.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 43),
              const SizedBox(height: 15),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 23 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondary,
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
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

  String get brandSubtitle =>
      isEnglish ? 'Your medication guide' : '건강한 복약 관리 도우미';

  String get todaySchedule => isEnglish ? 'Today\'s Medication' : '오늘의 복약 일정';
  String get noMedication => isEnglish
      ? 'No medicine registered\nScan a prescription'
      : '등록된 약이 없습니다\n처방전을 촬영해주세요';
  String get scanPrescription =>
      isEnglish ? 'Analyze with Camera' : '약 정보 촬영하기';
  String get scanPrescriptionSubtitle => isEnglish
      ? 'Choose a prescription or a loose pill'
      : '처방전 또는 낱알약을 촬영해주세요';
  String get savedMedication => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  String get savedMedicationSubtitle =>
      isEnglish ? 'Check saved medication info' : '저장된 복약 정보 확인';
  String get patientCaregiverLink =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  String get patientCaregiverLinkSubtitle => isEnglish
      ? 'Connect patient and caregiver medication schedules'
      : '환자와 보호자의 복약 일정을 연결';
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}
