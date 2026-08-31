import 'package:flutter/material.dart';

import 'medication_capture_options_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: input_prescription_ui_boundary.dart
// 역할: MedBuddy 홈 화면과 처방전 입력 진입점을 구성한다.

// 클래스명: InputPrescriptionUI
// 역할: 오늘의 복약 요약과 중복되지 않는 네 가지 빠른 기능을 제공하는 홈 화면이다.
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
  final DateTime Function()? nowProvider;
  final VoidCallback? onPrescriptionScanRequested;
  final VoidCallback? onPrescriptionGalleryRequested;
  final VoidCallback? onPillIdentificationRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onHealthRecommendationRequested;
  final VoidCallback? onMedicationReminderRequested;
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
    this.nowProvider,
    required this.onPrescriptionScanRequested,
    required this.onPrescriptionGalleryRequested,
    required this.onPillIdentificationRequested,
    required this.onTodayScheduleRequested,
    required this.onHealthRecommendationRequested,
    required this.onMedicationReminderRequested,
    required this.onUserSettingRequested,
  }) : isAnalyzing = false;

  const InputPrescriptionUI.analyzing({super.key, required this.statusMessage})
    : userSetting = const UserSetting(),
      todayMedicationScheduleList = const [],
      medicationReminderSettings = const {},
      todayMedicationCompletedCount = 0,
      todayMedicationTotalCount = 0,
      isTodayScheduleLoading = false,
      nowProvider = null,
      onPrescriptionScanRequested = null,
      onPrescriptionGalleryRequested = null,
      onPillIdentificationRequested = null,
      onTodayScheduleRequested = null,
      onHealthRecommendationRequested = null,
      onMedicationReminderRequested = null,
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
              child: LayoutBuilder(
                builder: (context, viewportConstraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(16) / 16;
                  final useCompactDashboard =
                      viewportConstraints.maxWidth >= 350 && textScale <= 1.1;
                  final dashboardActionSpacing = useCompactDashboard
                      ? viewportConstraints.maxHeight >= 600
                            ? 20.0
                            : 12.0
                      : 20.0;

                  return SingleChildScrollView(
                    key: const ValueKey('homeDashboardScrollView'),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      useCompactDashboard ? 12 : 24,
                      20,
                      useCompactDashboard ? 12 : 32,
                    ),
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
                              nowProvider: nowProvider,
                              compact: useCompactDashboard,
                              onTap: onTodayScheduleRequested,
                            ),
                            SizedBox(height: dashboardActionSpacing),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final useGrid =
                                    MediaQuery.sizeOf(context).width >= 350;
                                final useLargeTextGridLayout = textScale > 1.1;
                                final homeActions = <Widget>[
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homePrescriptionAnalysisCard',
                                    ),
                                    icon: Icons.document_scanner_outlined,
                                    title: text.prescriptionAnalysis,
                                    subtitle: text.prescriptionAnalysisSubtitle,
                                    tone: _HomeActionTone.primary,
                                    userSetting: userSetting,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    largeGridTitle:
                                        text.largePrescriptionAnalysis,
                                    onTap: () =>
                                        _showPrescriptionSourceOptions(context),
                                  ),
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homePillIdentificationCard',
                                    ),
                                    icon: Icons.medication_liquid_outlined,
                                    title: text.pillIdentification,
                                    subtitle: text.pillIdentificationSubtitle,
                                    tone: _HomeActionTone.mint,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    largeGridTitle:
                                        text.largePillIdentification,
                                    userSetting: userSetting,
                                    onTap: onPillIdentificationRequested,
                                  ),
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homeHealthRecommendationCard',
                                    ),
                                    icon: Icons.monitor_heart_outlined,
                                    title: text.healthRecommendation,
                                    subtitle: text.healthRecommendationSubtitle,
                                    tone: _HomeActionTone.lavender,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    largeGridTitle:
                                        text.largeHealthRecommendation,
                                    userSetting: userSetting,
                                    onTap: onHealthRecommendationRequested,
                                  ),
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homeMedicationReminderCard',
                                    ),
                                    icon: Icons.notifications_active_outlined,
                                    title: text.medicationReminder,
                                    subtitle: text.medicationReminderSubtitle,
                                    tone: _HomeActionTone.butter,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    largeGridTitle:
                                        text.largeMedicationReminder,
                                    userSetting: userSetting,
                                    onTap: onMedicationReminderRequested,
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
                                      primary: false,
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisSpacing: useCompactDashboard
                                          ? 10
                                          : 14,
                                      mainAxisSpacing: useCompactDashboard
                                          ? 10
                                          : 14,
                                      childAspectRatio: useLargeTextGridLayout
                                          ? 0.75
                                          : useCompactDashboard
                                          ? 1.25
                                          : 1,
                                      children: homeActions,
                                    ),
                                  ],
                                );
                              },
                            ),
                            SizedBox(height: useCompactDashboard ? 8 : 12),
                            _MedicationTipCard(text: text),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _showPrescriptionSourceOptions
  // 함수역할:
  // - 처방전 분석 카드에서 카메라와 갤러리 중 이미지 출처를 선택하게 한다.
  // - 낱알약 식별은 별도 빠른 기능 카드가 직접 처리한다.
  // 매개변수:
  // - context: 선택 화면 표시와 화면 활성 상태 확인에 사용할 BuildContext
  // 반환값:
  // - 없음
  Future<void> _showPrescriptionSourceOptions(BuildContext context) async {
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
                  key: const ValueKey('homeSettingsButton'),
                  customBorder: const CircleBorder(),
                  onTap: onSettingPressed,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
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

enum _HomeActionTone { primary, mint, lavender, butter }

class _HomeActionCard extends StatelessWidget {
  final Key? cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final _HomeActionTone tone;
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
    required this.tone,
    this.compact = false,
    this.largeTextGridLayout = false,
    this.largeGridTitle,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = switch (tone) {
      _HomeActionTone.primary => MedBuddyColors.primary,
      _HomeActionTone.mint => MedBuddyColors.successSurface,
      _HomeActionTone.lavender => MedBuddyColors.lavenderSurface,
      _HomeActionTone.butter => MedBuddyColors.butterSurface,
    };
    final foreground = tone == _HomeActionTone.primary
        ? Colors.white
        : MedBuddyColors.textStrong;
    final secondary = tone == _HomeActionTone.primary
        ? Colors.white.withValues(alpha: 0.9)
        : MedBuddyColors.textMuted;
    final accent = switch (tone) {
      _HomeActionTone.primary => Colors.white,
      _HomeActionTone.mint => MedBuddyColors.primaryDark,
      _HomeActionTone.lavender => MedBuddyColors.infoBlue,
      _HomeActionTone.butter => MedBuddyColors.reminderAccent,
    };
    final scale = userSetting.contentTextScale;
    final displayedTitle = largeTextGridLayout
        ? largeGridTitle ?? title
        : title;

    return Material(
      color: background,
      borderRadius: MedBuddyRadii.largeCard,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTap,
        child: Container(
          key: cardKey,
          width: double.infinity,
          constraints: compact ? null : const BoxConstraints(minHeight: 102),
          padding: compact
              ? EdgeInsets.all(largeTextGridLayout ? 8 : 10)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            boxShadow: MedBuddyShadows.soft,
            border: Border.all(
              color: tone == _HomeActionTone.primary
                  ? MedBuddyColors.primary
                  : MedBuddyColors.cardBorder,
            ),
          ),
          child: compact
              ? _buildCompactContent(
                  displayedTitle,
                  foreground,
                  secondary,
                  accent,
                  scale,
                )
              : _buildListContent(foreground, secondary, accent, scale),
        ),
      ),
    );
  }

  Widget _buildCompactContent(
    String displayedTitle,
    Color foreground,
    Color secondary,
    Color accent,
    double scale,
  ) {
    if (largeTextGridLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionIcon(icon: icon, tone: tone, color: accent, size: 52),
          const SizedBox(height: 5),
          Text(
            displayedTitle,
            maxLines: 3,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              height: 1.18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            _ActionIcon(icon: icon, tone: tone, color: accent, size: 40),
            const Spacer(),
            _ActionArrow(tone: tone, color: accent),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          displayedTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 14 * scale,
            height: 1.15,
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
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildListContent(
    Color foreground,
    Color secondary,
    Color accent,
    double scale,
  ) {
    return Row(
      children: [
        _ActionIcon(icon: icon, tone: tone, color: accent, size: 48),
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
        _ActionArrow(tone: tone, color: accent),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final _HomeActionTone tone;
  final Color color;
  final double size;

  const _ActionIcon({
    required this.icon,
    required this.tone,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone == _HomeActionTone.primary
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.6),
    );
  }
}

class _ActionArrow extends StatelessWidget {
  final _HomeActionTone tone;
  final Color color;

  const _ActionArrow({required this.tone, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: tone == _HomeActionTone.primary
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.82),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.arrow_forward_rounded, color: color, size: 18),
    );
  }
}

class _HomeText {
  final String language;

  const _HomeText(this.language);

  bool get isEnglish => language == 'en';

  String get prescriptionAnalysis =>
      isEnglish ? 'Prescription Analysis' : '처방전 분석';
  String get largePrescriptionAnalysis =>
      isEnglish ? 'Prescription\nAnalysis' : '처방전\n분석';
  String get prescriptionAnalysisSubtitle => isEnglish
      ? 'Scan a prescription or choose a saved image'
      : '처방전을 촬영하거나 사진에서 불러와요';
  String get pillIdentification =>
      isEnglish ? 'Loose-pill Identification' : '낱알약 식별';
  String get largePillIdentification =>
      isEnglish ? 'Loose-pill\nIdentification' : '낱알약\n식별';
  String get pillIdentificationSubtitle => isEnglish
      ? 'Photograph both sides to find likely matches'
      : '앞·뒷면을 촬영해 가능성 높은 약을 찾아요';
  String get healthRecommendation =>
      isEnglish ? 'Health Recommendations' : '건강 관리 추천';
  String get largeHealthRecommendation =>
      isEnglish ? 'Health\nRecommendations' : '건강 관리\n추천';
  String get healthRecommendationSubtitle => isEnglish
      ? 'Review food and activity guidance for your medications'
      : '복용 중인 약에 맞는 식사와 활동 팁을 확인해요';
  String get medicationReminder =>
      isEnglish ? 'Medication Reminders' : '복약 알림 설정';
  String get largeMedicationReminder =>
      isEnglish ? 'Medication\nReminders' : '복약 알림\n설정';
  String get medicationReminderSubtitle => isEnglish
      ? 'Adjust reminder times to fit your routine'
      : '복약 알림 시간을 내 생활에 맞게 조정해요';
  String get medicationTipTitle => isEnglish ? 'Medication tip' : '복약 팁';
  String get medicationTipBody => isEnglish
      ? 'Take medicine with water and follow your care instructions.'
      : '약은 충분한 물과 함께, 처방·복약지도에 맞춰 복용하세요.';
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}

// 홈 하단의 남는 공간에 짧은 안전 복약 안내를 제공한다.
class _MedicationTipCard extends StatelessWidget {
  final _HomeText text;

  const _MedicationTipCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final useCompactText =
        MediaQuery.textScalerOf(context).scale(16) / 16 <= 1.1;

    return Semantics(
      label: '${text.medicationTipTitle}. ${text.medicationTipBody}',
      container: true,
      child: Container(
        key: const ValueKey('homeMedicationTipCard'),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MedBuddyColors.successSurface,
          borderRadius: MedBuddyRadii.card,
          border: Border.all(color: MedBuddyColors.successBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: MedBuddyColors.mint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.lightbulb_outline_rounded,
                size: 19,
                color: MedBuddyColors.primaryDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ExcludeSemantics(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${text.medicationTipTitle} · ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: text.medicationTipBody),
                    ],
                  ),
                  maxLines: useCompactText ? 2 : null,
                  overflow: useCompactText
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                  style: const TextStyle(
                    color: MedBuddyColors.textBody,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 대시보드 첫 줄을 가로지르는 복약 현황 정보 영역이다.
class _HomeEncouragementPanel extends StatelessWidget {
  final UserSetting userSetting;
  final List<MedicationSchedule> schedules;
  final Map<String, MedicationAlarm> reminderSettings;
  final int completedCount;
  final int totalCount;
  final bool isLoading;
  final bool compact;
  final DateTime Function()? nowProvider;
  final VoidCallback? onTap;

  const _HomeEncouragementPanel({
    required this.userSetting,
    required this.schedules,
    required this.reminderSettings,
    required this.completedCount,
    required this.totalCount,
    required this.isLoading,
    this.compact = false,
    this.nowProvider,
    this.onTap,
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
      nowProvider: nowProvider,
    );
    final useStackedProgressLabel =
        MediaQuery.textScalerOf(context).scale(16) / 16 > 1.1;

    return Material(
      key: const ValueKey('homeEncouragementPanel'),
      color: MedBuddyColors.surface,
      borderRadius: MedBuddyRadii.largeCard,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: compact ? 190 : 260),
          padding: EdgeInsets.all(compact ? 14 : 24),
          decoration: BoxDecoration(
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
                    width: compact ? 42 : 46,
                    height: compact ? 42 : 46,
                    decoration: BoxDecoration(
                      color: MedBuddyColors.mint,
                      borderRadius: BorderRadius.circular(compact ? 14 : 15),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: MedBuddyColors.primaryDark,
                      size: compact ? 22 : 24,
                    ),
                  ),
                  SizedBox(width: compact ? 11 : 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dashboard.statusMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: compact ? 16 : 17,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 20),
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
              SizedBox(height: compact ? 6 : 9),
              ClipRRect(
                borderRadius: MedBuddyRadii.pill,
                child: LinearProgressIndicator(
                  value: dashboard.progress,
                  minHeight: compact ? 7 : 9,
                  color: MedBuddyColors.primary,
                  backgroundColor: MedBuddyColors.mint,
                ),
              ),
              SizedBox(height: compact ? 10 : 18),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 10 : 16),
                decoration: BoxDecoration(
                  color: MedBuddyColors.surfaceSubtle,
                  borderRadius: MedBuddyRadii.card,
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 34 : 38,
                      height: compact ? 34 : 38,
                      decoration: BoxDecoration(
                        color: dashboard.hasNextMedication
                            ? MedBuddyColors.mint
                            : MedBuddyColors.lavenderSurface,
                        borderRadius: BorderRadius.circular(compact ? 11 : 13),
                      ),
                      child: Icon(
                        dashboard.hasNextMedication
                            ? Icons.alarm_outlined
                            : Icons.event_available_outlined,
                        color: MedBuddyColors.primaryDark,
                        size: compact ? 19 : 21,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dashboard.nextMedicationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: compact ? 13 : 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: compact ? 2 : 3),
                          Text(
                            dashboard.nextMedicationGuide,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MedBuddyColors.textMuted,
                              fontSize: compact ? 11 : 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: MedBuddyColors.textSubtle,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    DateTime Function()? nowProvider,
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
    final now = nowProvider?.call() ?? DateTime.now();
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
          alarm: alarm,
          medications: pendingSchedules,
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

    pendingSlots.sort(
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    final upcomingSlots = pendingSlots
        .where((slot) => !slot.scheduledAt.isBefore(now))
        .toList(growable: false);
    final nextSlot = upcomingSlots.isNotEmpty
        ? upcomingSlots.first
        : pendingSlots.last;
    final isPastDue = nextSlot.scheduledAt.isBefore(now);
    final timeLabel =
        '${nextSlot.scheduledAt.hour.toString().padLeft(2, '0')}:${nextSlot.scheduledAt.minute.toString().padLeft(2, '0')}';
    final medicationName = nextSlot.medications.first.displayNameForLanguage(
      isEnglish ? 'en' : 'ko',
    );
    final additionalMedicationCount = nextSlot.medications.length - 1;
    final medicationSummary = additionalMedicationCount == 0
        ? medicationName
        : isEnglish
        ? '$medicationName and $additionalMedicationCount more'
        : '$medicationName 외 $additionalMedicationCount개';
    final statusMessage = isPastDue
        ? (isEnglish
              ? 'You have a missed medication to check'
              : '미복용한 약을 확인해주세요')
        : (isEnglish
              ? 'You are keeping up with your medication'
              : '오늘도 복약을 꾸준히 이어가고 있어요');
    final nextMedicationLabel = isPastDue
        ? (isEnglish ? 'Missed dose check' : '미복용 확인')
        : isEnglish
        ? (nextSlot.alarm.isEnabled
              ? 'Next medication alert'
              : 'Next medication')
        : (nextSlot.alarm.isEnabled ? '다음 복약 알림' : '다음 복약 일정');

    return _HomeDashboardSummary(
      progress: progress,
      progressLabel: progressLabel,
      statusMessage: statusMessage,
      hasNextMedication: true,
      nextMedicationLabel: nextMedicationLabel,
      nextMedicationGuide: isEnglish
          ? '${_slotLabel(nextSlot.slotKey, isEnglish: true)} $timeLabel · $medicationSummary\n${isPastDue ? 'Check your prescription guidance before taking a missed dose.' : 'Take it on time.'}'
          : '${_slotLabel(nextSlot.slotKey, isEnglish: false)} $timeLabel · $medicationSummary\n${isPastDue ? '놓친 복약은 임의로 추가 복용하지 말고 처방·복약지도를 확인하세요.' : '시간에 맞춰 챙겨드세요.'}',
    );
  }

  static String _slotLabel(String slotKey, {required bool isEnglish}) {
    if (isEnglish) {
      return switch (slotKey) {
        'morning' => 'Morning',
        'lunch' => 'Lunch',
        'evening' => 'Evening',
        'bedtime' => 'Bedtime',
        _ => slotKey,
      };
    }
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
  final MedicationAlarm alarm;
  final List<MedicationSchedule> medications;

  const _DashboardPendingSlot({
    required this.slotKey,
    required this.scheduledAt,
    required this.alarm,
    required this.medications,
  });
}
