// 파일명: input_prescription_ui_boundary.dart
// 역할: 처방전, 낱알약과 직접 등록 중 입력 방법을 선택하는 화면을 제공한다.

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
  final VoidCallback? onManualMedicationRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onPatientCaregiverLinkRequested;
  final VoidCallback? onNearbyPharmacyRequested;
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
    this.onManualMedicationRequested,
    required this.onTodayScheduleRequested,
    required this.onSavedMedicationRequested,
    required this.onPatientCaregiverLinkRequested,
    this.onNearbyPharmacyRequested,
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
      onManualMedicationRequested = null,
      onTodayScheduleRequested = null,
      onSavedMedicationRequested = null,
      onPatientCaregiverLinkRequested = null,
      onNearbyPharmacyRequested = null,
      onUserSettingRequested = null,
      isAnalyzing = true;

  @override
  Widget build(BuildContext context) {
    final text = _HomeText(userSetting.language);
    final encouragement = _HomeEncouragement.forToday(
      isEnglish: text.isEnglish,
    );

    if (isAnalyzing) {
      return _buildAnalyzingScreen(text);
    }

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _HomeHeader(text: text, onSettingPressed: onUserSettingRequested),
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
                        _HomeEncouragementPanel(encouragement: encouragement),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final textScale =
                                MediaQuery.textScalerOf(context).scale(16) / 16;
                            final useGrid =
                                MediaQuery.sizeOf(context).width >= 350 &&
                                textScale <= 1.1;
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
                              ),
                              _HomeActionCard(
                                cardKey: const ValueKey('homeCaptureCard'),
                                icon: Icons.photo_camera_outlined,
                                title: text.scanPrescription,
                                subtitle: text.scanPrescriptionSubtitle,
                                filled: true,
                                compact: useGrid,
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

                            return GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.84,
                              children: homeActions,
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _HomeMedicationTipCard(isEnglish: text.isEnglish),
                        if (onNearbyPharmacyRequested != null) ...[
                          const SizedBox(height: 14),
                          _HomeActionCard(
                            cardKey: const ValueKey('homeNearbyPharmacyCard'),
                            icon: Icons.local_pharmacy_outlined,
                            title: text.nearbyPharmacy,
                            subtitle: text.nearbyPharmacySubtitle,
                            filled: false,
                            userSetting: userSetting,
                            onTap: onNearbyPharmacyRequested,
                          ),
                        ],
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
  // - 공통 선택 화면에서 처방전 분석, 낱알약 식별, 직접 등록 작업을 선택하게 한다.
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
    if (task == MedicationCaptureTask.manual) {
      onManualMedicationRequested?.call();
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
  final _HomeText text;
  final VoidCallback? onSettingPressed;

  const _HomeHeader({required this.text, required this.onSettingPressed});

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
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MedBuddy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      text.brandSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: MedBuddyColors.textSubtle,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
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
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _HomeActionCard({
    this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    this.compact = false,
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
              ? const EdgeInsets.all(14)
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
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: filled
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: foreground, size: 27),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15 * scale,
                        height: 1.18,
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
                        fontSize: 11 * scale,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      : '처방전 또는 낱알약을 촬영해 분석하세요';
  String get savedMedication => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  String get savedMedicationSubtitle =>
      isEnglish ? 'Check saved medication info' : '저장해 둔 약 정보를 확인하세요';
  String get patientCaregiverLink =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  String get patientCaregiverLinkSubtitle => isEnglish
      ? 'Connect patient and caregiver medication schedules'
      : '환자와 보호자의 복약 일정을 연결';
  String get nearbyPharmacy => isEnglish ? 'Nearby Pharmacy' : '근처 운영 약국';
  String get nearbyPharmacySubtitle => isEnglish
      ? 'Find pharmacies near your current location'
      : '현재 위치에서 가까운 약국 찾기';
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}

// 홈 화면에서만 사용하는 가벼운 안내 문구다. 계정이나 서버 상태와 무관하게
// 하루 동안 같은 문구를 유지해 화면이 다시 그려져도 내용이 흔들리지 않는다.
class _HomeEncouragement {
  final String eyebrow;
  final String message;

  const _HomeEncouragement({required this.eyebrow, required this.message});

  factory _HomeEncouragement.forToday({required bool isEnglish}) {
    const koreanMessages = [
      '작은 한 알이 건강한 하루를 만듭니다.',
      '물 한 잔과 함께 오늘의 복약을 시작해요.',
      '약속한 시간에 챙기는 습관이 건강을 지켜줘요.',
      '천천히, 꾸준히. 건강한 변화는 매일 쌓여요.',
      '오늘도 나를 위한 복약을 잊지 마세요.',
    ];
    const englishMessages = [
      'Small steps build a healthier day.',
      'Start today\'s dose with a glass of water.',
      'A timely habit helps care for your health.',
      'Slow and steady, healthy changes add up.',
      'Remember to take a moment for your health today.',
    ];
    final messages = isEnglish ? englishMessages : koreanMessages;
    final index =
        DateTime.now().difference(DateTime(2024)).inDays.abs() %
        messages.length;
    return _HomeEncouragement(
      eyebrow: isEnglish ? 'A note from MedBuddy' : 'MedBuddy의 작은 응원',
      message: messages[index],
    );
  }
}

// 대시보드 첫 줄을 가로지르는 안내 영역이며, 동작을 수행하지 않는 정보 전용 섹션이다.
class _HomeEncouragementPanel extends StatelessWidget {
  final _HomeEncouragement encouragement;

  const _HomeEncouragementPanel({required this.encouragement});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18A66A), MedBuddyColors.primaryDark],
        ),
        borderRadius: MedBuddyRadii.largeCard,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  encouragement.eyebrow,
                  style: const TextStyle(
                    color: Color(0xFFD6F2E3),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  encouragement.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
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

class _HomeMedicationTipCard extends StatelessWidget {
  final bool isEnglish;

  const _HomeMedicationTipCard({required this.isEnglish});

  @override
  Widget build(BuildContext context) {
    final title = isEnglish ? 'Your medication guide' : '복약 관리 팁';
    final message = isEnglish
        ? 'A prescription or pill photo can make medication details easier to review.'
        : '처방전이나 낱알약 사진을 촬영하면 약 정보를 더 쉽게 확인할 수 있어요.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MedBuddyColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: MedBuddyColors.primaryDark,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 13,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
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
