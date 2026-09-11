// File Name: input_prescription_ui_boundary.dart
// Role: UI boundaries and helpers for the home medication dashboard and medication input entry points.

import 'package:flutter/material.dart';

import 'medication_capture_options_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: input_prescription_ui_boundary.dart
// 역할: MedBuddy 홈 화면과 처방전 입력 진입점을 구성한다.

// Class Name: InputPrescriptionUI
// Role: Represents medication status and quick medication input or lookup actions.
// Responsibilities:
// - Applies the user's home wording and text size.
// - Offers camera and gallery prescription input.
// - Replaces input with progress while OCR is running.
// Attributes:
// - statusMessage (String): Visible wording for the current result, error, or state.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - todayMedicationScheduleList (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
// - medicationReminderSettings (Map<String, MedicationAlarm>): Reminder settings indexed by dose-slot key.
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
  final ValueChanged<PillCaptureMode>? onPillIdentificationRequested;
  final VoidCallback? onManualMedicationRequested;
  final VoidCallback? onTodayScheduleRequested;
  final Future<void> Function(String slotKey)?
  onNextMedicationCompleteRequested;
  final bool isNextMedicationCompletionLoading;
  final VoidCallback? onNearbyPharmacyRequested;
  final VoidCallback? onHealthRecommendationRequested;
  final VoidCallback? onMedicationReminderRequested;
  final VoidCallback? onUserSettingRequested;
  final bool isAnalyzing;

  // Function Name: InputPrescriptionUI
  // Description: Initializes medication status and quick medication input or lookup actions with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - statusMessage (String): Visible wording for the current result, error, or state.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // - todayMedicationScheduleList (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - medicationReminderSettings (Map<String, MedicationAlarm>): Reminder settings indexed by dose-slot key.
  // - todayMedicationCompletedCount (int): Number of completed doses.
  // - todayMedicationTotalCount (int): Total scheduled doses or operation items.
  // - isTodayScheduleLoading (bool): Whether to show the in-progress state.
  // - nowProvider (DateTime Function()?): Clock function; the device's current time is used when omitted.
  // - onPrescriptionScanRequested (VoidCallback?): Callback requesting prescription capture or recapture through the guided camera.
  // - onPrescriptionGalleryRequested (VoidCallback?): Callback selecting a prescription photo from the gallery.
  // - onPillIdentificationRequested (ValueChanged<PillCaptureMode>?): 선택한 촬영 방식의 알약 식별을 여는 콜백.
  // - onManualMedicationRequested (VoidCallback?): Callback opening manual medication and schedule entry.
  // - onTodayScheduleRequested (VoidCallback?): Callback opening today's medication schedule.
  // - onNextMedicationCompleteRequested (Future<void> Function(String slotKey)?): Callback requesting completion of the next or selected dose slot.
  // - isNextMedicationCompletionLoading (bool): Whether the associated save, analysis, or medication update is in progress.
  // - onNearbyPharmacyRequested (VoidCallback?): Callback opening nearby-pharmacy search.
  // - onHealthRecommendationRequested (VoidCallback?): Callback opening health recommendations.
  // - onMedicationReminderRequested (VoidCallback?): Callback opening the associated slot's reminder settings.
  // - onUserSettingRequested (VoidCallback?): Callback opening user settings.
  // Returns: Initialized InputPrescriptionUI instance.
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
    this.onManualMedicationRequested,
    required this.onTodayScheduleRequested,
    this.onNextMedicationCompleteRequested,
    this.isNextMedicationCompletionLoading = false,
    this.onNearbyPharmacyRequested,
    required this.onHealthRecommendationRequested,
    required this.onMedicationReminderRequested,
    required this.onUserSettingRequested,
  }) : isAnalyzing = false;

  // Function Name: InputPrescriptionUI.analyzing
  // Description: Initializes medication status and quick medication input or lookup actions with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - statusMessage (String): Visible wording for the current result, error, or state.
  // Returns: Initialized InputPrescriptionUI instance.
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
      onManualMedicationRequested = null,
      onTodayScheduleRequested = null,
      onNextMedicationCompleteRequested = null,
      isNextMedicationCompletionLoading = false,
      onNearbyPharmacyRequested = null,
      onHealthRecommendationRequested = null,
      onMedicationReminderRequested = null,
      onUserSettingRequested = null,
      isAnalyzing = true;

  // 함수이름: build
  // 함수역할: 복약 현황과 빠른 기능을 표시하고, 큰 글씨에서는 설명 길이에 맞춰 카드 높이를 정한다.
  // 매개변수:
  // - context (BuildContext): 화면 크기와 접근성 배율을 제공하는 위젯 위치.
  // 반환값: 복약 현황과 입력·조회 기능을 포함한 스크롤 가능한 홈 화면.
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
            _HomeHeader(text: text, onSettingPressed: onUserSettingRequested),
            Expanded(
              child: LayoutBuilder(
                // 함수이름: 홈 스크롤 영역 builder
                // 함수역할: 화면 너비에 맞춰 여백을 정하고 접근성 배율을 카드에 전달한다.
                // 매개변수: context (BuildContext), viewportConstraints (BoxConstraints): 화면 문맥과 사용 가능한 크기.
                // 반환값: 복약 현황과 기능 카드가 배치된 스크롤 영역.
                builder: (context, viewportConstraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(16) / 16;
                  final useCompactDashboard =
                      viewportConstraints.maxWidth >= 350;
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
                              onCompleteRequested:
                                  onNextMedicationCompleteRequested,
                              isCompletionLoading:
                                  isNextMedicationCompletionLoading,
                            ),
                            SizedBox(height: dashboardActionSpacing),
                            LayoutBuilder(
                              // 함수이름: 빠른 기능 영역 builder
                              // 함수역할: 좁은 화면은 한 열, 일반 화면은 두 열로 배치하며 큰 글씨의 행 높이는 내용에 맞춘다.
                              // 매개변수: context (BuildContext), constraints (BoxConstraints): 문맥과 실제 콘텐츠 너비.
                              // 반환값: 글씨 크기에 따라 설명이 사라지지 않는 기능 카드 목록.
                              builder: (context, constraints) {
                                final useGrid = constraints.maxWidth >= 310;
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
                                    // Function Name: build.onTap callback
                                    // Description: Connects medication status and quick medication input or lookup actions to the captured operation `_showAnalysisTaskOptions(context)`.
                                    // Parameters:
                                    // - None.
                                    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                                    onTap: () =>
                                        _showAnalysisTaskOptions(context),
                                  ),
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homeMedicationReminderCard',
                                    ),
                                    icon: Icons.notifications_active_outlined,
                                    title: text.medicationReminder,
                                    subtitle: text.medicationReminderSubtitle,
                                    tone: _HomeActionTone.mint,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    userSetting: userSetting,
                                    onTap: onMedicationReminderRequested,
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
                                    userSetting: userSetting,
                                    onTap: onHealthRecommendationRequested,
                                  ),
                                  _HomeActionCard(
                                    cardKey: const ValueKey(
                                      'homeNearbyPharmacyCard',
                                    ),
                                    icon: Icons.local_pharmacy_outlined,
                                    title: text.nearbyPharmacy,
                                    subtitle: text.nearbyPharmacySubtitle,
                                    tone: _HomeActionTone.butter,
                                    compact: useGrid,
                                    largeTextGridLayout: useLargeTextGridLayout,
                                    userSetting: userSetting,
                                    onTap: onNearbyPharmacyRequested,
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

                                if (useLargeTextGridLayout) {
                                  // 두 행만 내용 높이를 측정해 설명을 보존하고 같은 행의 카드 높이를 맞춘다.
                                  const gap = 10.0;
                                  final cardWidth =
                                      (constraints.maxWidth - gap) / 2;
                                  return Column(
                                    children: [
                                      for (
                                        int index = 0;
                                        index < 4;
                                        index += 2
                                      ) ...[
                                        if (index > 0)
                                          const SizedBox(height: gap),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: cardWidth / 1.25,
                                          ),
                                          child: IntrinsicHeight(
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: homeActions[index],
                                                ),
                                                const SizedBox(width: gap),
                                                Expanded(
                                                  child: homeActions[index + 1],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
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
                                      childAspectRatio: useCompactDashboard
                                          ? 1.25
                                          : 1,
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _showAnalysisTaskOptions
  // 함수역할: 공통 선택 화면에서 처방전 분석, 낱알약 식별, 직접 등록 작업을 선택하게 한다. 처방전 분석을 선택하면 카메라와 갤러리 중 이미지 출처를 추가로 선택하게 한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showAnalysisTaskOptions(BuildContext context) async {
    final task = await showMedicationCaptureTaskOptions(
      context: context,
      userSetting: userSetting,
    );

    if (!context.mounted || task == null) {
      return;
    }
    if (task == MedicationCaptureTask.multiplePills ||
        task == MedicationCaptureTask.individualPills) {
      onPillIdentificationRequested?.call(
        task == MedicationCaptureTask.multiplePills
            ? PillCaptureMode.singlePhoto
            : PillCaptureMode.individualPhotos,
      );
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

  // Function Name: _buildAnalyzingScreen
  // Description: Replaces home input with OCR progress guidance and indicators.
  // Parameters:
  // - text (_HomeText): Localized labels used by this section.
  // Returns: Widget tree for medication status and quick medication input or lookup actions.
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

// Class Name: _HomeHeader
// Role: Represents the home heading and supporting top-bar content.
// Responsibilities:
// - Composes the home heading and supporting top-bar content using the display values and actions supplied by its parent.
// Attributes:
// - onSettingPressed (VoidCallback?): Callback opening user settings.
class _HomeHeader extends StatelessWidget {
  final _HomeText text;
  final VoidCallback? onSettingPressed;

  // 함수이름: _HomeHeader
  // 함수역할: 홈 제목과 앱 버전·설정 관련 상단 콘텐츠에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_HomeText): 해당 화면 구역의 언어별 표시 문구.
  // - onSettingPressed (VoidCallback?): 사용자 환경설정 화면을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _HomeHeader 인스턴스.
  const _HomeHeader({required this.text, required this.onSettingPressed});

  // Function Name: build
  // Description: Renders the home heading and supporting top-bar content from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the home heading and supporting top-bar content.
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
                        letterSpacing: -0.3,
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

// Class Name: _HomeActionTone
// Role: Represents background and icon color combinations for home quick actions.
// Responsibilities:
// - Enumerates and distinguishes the supported options for background and icon color combinations for home quick actions: primary, mint, lavender, butter.
enum _HomeActionTone { primary, mint, lavender, butter }

// Class Name: _HomeActionCard
// Role: Represents a home quick action with its icon and title.
// Responsibilities:
// - Composes a home quick action with its icon and title using the display values and actions supplied by its parent.
// Attributes:
// - cardKey (Key?): Widget identity used to distinguish elements and preserve state.
// - icon (IconData): Icon shown in normal or selected state.
// - title (String): Heading shown for the screen, section, or item.
// - subtitle (String): Supporting explanation or account detail below the primary label.
class _HomeActionCard extends StatelessWidget {
  final Key? cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final _HomeActionTone tone;
  final bool compact;
  final bool largeTextGridLayout;
  final UserSetting userSetting;
  final VoidCallback? onTap;

  // 함수이름: _HomeActionCard
  // 함수역할: 동일한 제목·설명을 일반 글씨와 큰 글씨 모두에서 사용할 기능 카드를 만든다.
  // 매개변수:
  // - cardKey (Key?), icon (IconData), title, subtitle (String): 카드 식별자와 표시할 내용.
  // - tone (_HomeActionTone), compact (bool): 색상과 두 열 카드 사용 여부.
  // - largeTextGridLayout (bool): 제목과 설명을 줄 수 제한 없이 표시할지 여부.
  // - userSetting (UserSetting), onTap (VoidCallback?): 사용자 설정과 기능 실행 동작.
  // 반환값: 초기화된 홈 기능 카드.
  const _HomeActionCard({
    this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    this.compact = false,
    this.largeTextGridLayout = false,
    required this.userSetting,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 기능별 색상을 적용하고 목록형 또는 두 열 카드의 전체 설명을 구성한다.
  // 매개변수: context (BuildContext): 접근성 배율과 테마를 상속하는 위젯 위치.
  // 반환값: 제목·설명·아이콘·이동 화살표를 포함한 기능 카드.
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
              ? const EdgeInsets.all(10)
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
              ? _buildCompactContent(foreground, secondary, accent, scale)
              : _buildListContent(foreground, secondary, accent, scale),
        ),
      ),
    );
  }

  // 함수이름: _buildCompactContent
  // 함수역할: 큰 글씨에서도 아이콘·화살표·제목·설명을 유지하고 텍스트를 자연스럽게 줄바꿈한다.
  // 매개변수:
  // - foreground, secondary, accent (Color): 제목·설명·아이콘에 사용할 색상.
  // - scale (double): 콘텐츠 배율. 전역 접근성 배율은 Text가 별도로 상속한다.
  // 반환값: 고정 높이에 맞춰 축소하지 않는 카드 내부 위젯.
  Widget _buildCompactContent(
    Color foreground,
    Color secondary,
    Color accent,
    double scale,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          title,
          maxLines: largeTextGridLayout ? null : 2,
          overflow: largeTextGridLayout
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
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
          maxLines: largeTextGridLayout ? null : 2,
          overflow: largeTextGridLayout
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
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

  // 함수이름: _buildListContent
  // 함수역할: 좁은 화면의 한 열 카드에서도 큰 글씨의 제목과 설명을 생략하지 않는다.
  // 매개변수:
  // - foreground, secondary, accent (Color): 제목·설명·아이콘 색상.
  // - scale (double): 전역 접근성 배율과 중복되지 않는 콘텐츠 배율.
  // 반환값: 내용 높이만큼 늘어나는 목록형 카드 내부 위젯.
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
                maxLines: largeTextGridLayout ? null : 1,
                overflow: largeTextGridLayout
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: largeTextGridLayout ? null : 2,
                overflow: largeTextGridLayout
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
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

// Class Name: _ActionIcon
// Role: Represents the color-coded icon for a home quick action.
// Responsibilities:
// - Composes the color-coded icon for a home quick action using the display values and actions supplied by its parent.
// Attributes:
// - icon (IconData): Icon shown in normal or selected state.
// - tone (_HomeActionTone): Accent and background palette for the home action.
// - color (Color): Foreground or accent color applied to text, icons, or state guidance.
// - size (double): Display dimensions of the widget or canvas.
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final _HomeActionTone tone;
  final Color color;
  final double size;

  // Function Name: _ActionIcon
  // Description: Initializes the color-coded icon for a home quick action with the supplied configuration.
  // Parameters:
  // - icon (IconData): Icon shown in normal or selected state.
  // - tone (_HomeActionTone): Accent and background palette for the home action.
  // - color (Color): Foreground or accent color applied to text, icons, or state guidance.
  // - size (double): Display dimensions of the widget or canvas.
  // Returns: Initialized _ActionIcon instance.
  const _ActionIcon({
    required this.icon,
    required this.tone,
    required this.color,
    required this.size,
  });

  // Function Name: build
  // Description: Renders the color-coded icon for a home quick action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the color-coded icon for a home quick action.
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

// Class Name: _ActionArrow
// Role: Represents the navigation arrow on a home quick action.
// Responsibilities:
// - Composes the navigation arrow on a home quick action using the display values and actions supplied by its parent.
// Attributes:
// - tone (_HomeActionTone): Accent and background palette for the home action.
// - color (Color): Foreground or accent color applied to text, icons, or state guidance.
class _ActionArrow extends StatelessWidget {
  final _HomeActionTone tone;
  final Color color;

  // Function Name: _ActionArrow
  // Description: Initializes the navigation arrow on a home quick action with the supplied configuration.
  // Parameters:
  // - tone (_HomeActionTone): Accent and background palette for the home action.
  // - color (Color): Foreground or accent color applied to text, icons, or state guidance.
  // Returns: Initialized _ActionArrow instance.
  const _ActionArrow({required this.tone, required this.color});

  // Function Name: build
  // Description: Renders the navigation arrow on a home quick action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the navigation arrow on a home quick action.
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

// Class Name: _HomeText
// Role: Represents localized wording for the home medication dashboard and medication input entry points.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for the home medication dashboard and medication input entry points.
// Attributes:
// - language (String): Language code selecting visible wording.
class _HomeText {
  final String language;

  // 함수이름: _HomeText
  // 함수역할: 홈 대시보드의 복약 요약과 약 정보 입력 진입에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _HomeText 인스턴스.
  const _HomeText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: brandSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "건강한 복약 관리 도우미" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get brandSubtitle =>
      isEnglish ? 'Your medication guide' : '건강한 복약 관리 도우미';
  // 함수이름: prescriptionAnalysis
  // 함수역할: 처방전·알약 식별·직접 등록을 포함하는 홈 진입점의 이름을 번역한다.
  // 매개변수: 없음. 반환값: 현재 언어의 카드 제목.
  String get prescriptionAnalysis =>
      isEnglish ? 'Add or Identify Medication' : '약 등록·식별';
  // 함수이름: prescriptionAnalysisSubtitle
  // 함수역할: 약 정보 입력과 식별 방법을 카드 설명으로 안내한다.
  // 매개변수: 없음. 반환값: 현재 언어의 카드 설명.
  String get prescriptionAnalysisSubtitle => isEnglish
      ? 'Use a prescription, pill photo, or manual entry'
      : '처방전·알약 사진 또는 직접 입력으로 등록해요';
  // Function Name: healthRecommendation
  // Description: Provides localized wording for "Health Recommendations" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get healthRecommendation =>
      isEnglish ? 'Health Recommendations' : '건강 관리 추천';
  // Function Name: healthRecommendationSubtitle
  // Description: Provides localized wording for "Review food and activity guidance for your medications" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get healthRecommendationSubtitle => isEnglish
      ? 'Review food and activity guidance for your medications'
      : '복용 중인 약에 맞는 식사와 활동 팁을 확인해요';
  // Function Name: medicationReminder
  // Description: Provides localized wording for "Medication Reminders" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get medicationReminder =>
      isEnglish ? 'Medication Reminders' : '복약 알림 설정';
  // Function Name: medicationReminderSubtitle
  // Description: Provides localized wording for "Adjust reminder times to fit your routine" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get medicationReminderSubtitle => isEnglish
      ? 'Adjust reminder times to fit your routine'
      : '복약 알림 시간을 내 생활에 맞게 조정해요';
  // 함수이름: nearbyPharmacy
  // 함수역할: 현재 언어와 입력값에 맞춰 "근처 운영 약국" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nearbyPharmacy => isEnglish ? 'Nearby Pharmacy' : '근처 운영 약국';
  // 함수이름: nearbyPharmacySubtitle
  // 함수역할: 2×2 기능 카드에서 읽기 쉬운 약국 탐색 설명을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nearbyPharmacySubtitle =>
      isEnglish ? 'Find an open pharmacy nearby' : '가까운 운영 약국을 찾아요';
  // 함수이름: analyzingTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 인식 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}

// Class Name: _HomeEncouragementPanel
// Role: Represents the home dashboard's medication status and completion encouragement.
// Responsibilities:
// - Composes the home dashboard's medication status and completion encouragement using the display values and actions supplied by its parent.
// Attributes:
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
// - reminderSettings (Map<String, MedicationAlarm>): Reminder settings indexed by dose-slot key.
// - completedCount (int): Number of completed doses.
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
  final Future<void> Function(String slotKey)? onCompleteRequested;
  final bool isCompletionLoading;

  // Function Name: _HomeEncouragementPanel
  // Description: Initializes the home dashboard's medication status and completion encouragement with the supplied configuration.
  // Parameters:
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - reminderSettings (Map<String, MedicationAlarm>): Reminder settings indexed by dose-slot key.
  // - completedCount (int): Number of completed doses.
  // - totalCount (int): Total scheduled doses or operation items.
  // - isLoading (bool): Whether to show the in-progress state.
  // - compact (bool): Whether compact card or header layout is used.
  // - nowProvider (DateTime Function()?): Clock function; the device's current time is used when omitted.
  // - onTap (VoidCallback?): Callback executing the item's documented primary action.
  // - onCompleteRequested (Future<void> Function(String slotKey)?): Callback requesting completion of the next or selected dose slot.
  // - isCompletionLoading (bool): Whether the associated save, analysis, or medication update is in progress.
  // Returns: Initialized _HomeEncouragementPanel instance.
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
    this.onCompleteRequested,
    this.isCompletionLoading = false,
  });

  // 함수이름: build
  // 함수역할: 복약 현황과 다음 일정을 표시하고 안내 문구를 생략 없이 줄바꿈해 보여준다.
  // 매개변수: context (BuildContext): 접근성 배율과 화면 테마를 제공하는 문맥.
  // 반환값: 여백은 유지하면서 내용에 따라 높이가 정해지는 복약 현황 패널.
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEnglish ? 'Today\'s progress' : '오늘의 복약 진행률',
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
              if (dashboard.nextSlotKey != null &&
                  onCompleteRequested != null) ...[
                SizedBox(height: compact ? 10 : 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const ValueKey('homeNextSlotCompletionButton'),
                    onPressed: isCompletionLoading
                        ? null
                        // Function Name: build.onPressed callback
                        // Description: Supplies `onCompleteRequested!(dashboard.nextSlotKey!)` from the captured state of the home dashboard's medication status and completion encouragement.
                        // Parameters:
                        // - None.
                        // Returns: The value of `onCompleteRequested!(dashboard.nextSlotKey!)`.
                        : () => onCompleteRequested!(dashboard.nextSlotKey!),
                    icon: isCompletionLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.done_all_rounded),
                    label: Text(
                      isCompletionLoading
                          ? (isEnglish ? 'Saving...' : '저장 중...')
                          : (isEnglish ? 'Taken' : '복용했어요'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: MedBuddyColors.primary
                          .withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: MedBuddyRadii.pill,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Class Name: _HomeDashboardSummary
// Role: Represents home summary text, the next dose slot, and batch completion state.
// Responsibilities:
// - Maps a dose-slot key to its Korean or English name, preserving unknown keys.
// Attributes:
// - progress (double): Completion fraction from zero to one.
// - progressLabel (String): Text showing completed and total counts.
// - statusMessage (String): Visible wording for the current result, error, or state.
// - hasNextMedication (bool): Whether the summary requires user attention or dose action.
class _HomeDashboardSummary {
  static const _slotOrder = ['morning', 'lunch', 'evening', 'bedtime'];

  final double progress;
  final String progressLabel;
  final String statusMessage;
  final bool hasNextMedication;
  final String? nextSlotKey;
  final String nextMedicationLabel;
  final String nextMedicationGuide;

  // Function Name: _HomeDashboardSummary
  // Description: Combines the supplied values for home summary text, the next dose slot, and batch completion state in a _HomeDashboardSummary instance.
  // Parameters:
  // - progress (double): Completion fraction from zero to one.
  // - progressLabel (String): Text showing completed and total counts.
  // - statusMessage (String): Visible wording for the current result, error, or state.
  // - hasNextMedication (bool): Whether the summary requires user attention or dose action.
  // - nextSlotKey (String?): Key identifying morning, lunch, evening, or bedtime.
  // - nextMedicationLabel (String): Heading for the next-dose or missed-dose state.
  // - nextMedicationGuide (String): Medication, time, and safety guidance for the next dose.
  // Returns: Initialized _HomeDashboardSummary instance.
  const _HomeDashboardSummary({
    required this.progress,
    required this.progressLabel,
    required this.statusMessage,
    required this.hasNextMedication,
    required this.nextSlotKey,
    required this.nextMedicationLabel,
    required this.nextMedicationGuide,
  });

  // Function Name: _HomeDashboardSummary.from
  // Description: Clamps completed doses to the total and summarizes the next upcoming slot or latest overdue slot.
  // Parameters:
  // - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - reminderSettings (Map<String, MedicationAlarm>): Reminder settings indexed by dose-slot key.
  // - completedCount (int): Number of completed doses.
  // - totalCount (int): Total scheduled doses or operation items.
  // - isLoading (bool): Whether to show the in-progress state.
  // - isEnglish (bool): Whether English wording is selected; false selects Korean.
  // - nowProvider (DateTime Function()?): Clock function; the device's current time is used when omitted.
  // Returns: Initialized _HomeDashboardSummary instance.
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
        nextSlotKey: null,
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
            // 함수이름: initializer.where callback
            // 함수역할: 홈 요약 문구·다음 시간대·일괄 완료 상태에 대해 `schedule.slotKeys.contains(slotKey) && !schedule.isSlotCompleted(slotKey)` 조건으로 컬렉션 항목을 판별한다.
            // 매개변수:
            // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
            // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
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
        nextSlotKey: null,
        nextMedicationLabel: isEnglish
            ? 'No upcoming medication'
            : '다음 복약 일정이 없어요',
        nextMedicationGuide: isEnglish
            ? 'Take time to rest and recharge.'
            : '남은 시간도 편안하게 보내세요.',
      );
    }

    pendingSlots.sort(
      // Function Name: initializer.sort callback
      // Description: Computes the ordering comparison for home summary text, the next dose slot, and batch completion state with `left.scheduledAt.compareTo(right.scheduledAt)`.
      // Parameters:
      // - left (inferred by callback contract): One of the two items being compared for ordering.
      // - right (inferred by callback contract): One of the two items being compared for ordering.
      // Returns: The ordering comparison passed back to the collection operation.
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    final upcomingSlots = pendingSlots
        // Function Name: initializer.where callback
        // Description: Checks the collection condition `!slot.scheduledAt.isBefore(now)` for home summary text, the next dose slot, and batch completion state.
        // Parameters:
        // - slot (inferred by callback contract): Dose-slot identity, time, and presentation data.
        // Returns: Boolean predicate result for the supplied item.
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
      nextSlotKey: nextSlot.slotKey,
      nextMedicationLabel: nextMedicationLabel,
      nextMedicationGuide: isEnglish
          ? '${_slotLabel(nextSlot.slotKey, isEnglish: true)} $timeLabel · $medicationSummary\n${isPastDue ? 'Check your prescription guidance before taking a missed dose.' : 'Take it on time.'}'
          : '${_slotLabel(nextSlot.slotKey, isEnglish: false)} $timeLabel · $medicationSummary\n${isPastDue ? '놓친 복약은 임의로 추가 복용하지 말고 처방·복약지도를 확인하세요.' : '시간에 맞춰 챙겨드세요.'}',
    );
  }

  // Function Name: _slotLabel
  // Description: Maps a dose-slot key to its Korean or English name, preserving unknown keys.
  // Parameters:
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // - isEnglish (bool): Whether English wording is selected; false selects Korean.
  // Returns: The formatted display text or identifier described above.
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

// Class Name: _DashboardPendingSlot
// Role: Represents a pending dashboard slot and its medication count.
// Responsibilities:
// - Groups the supplied field values for a pending dashboard slot and its medication count in a single object.
// Attributes:
// - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
// - scheduledAt (DateTime): Scheduled date and time for the dose slot.
// - alarm (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
// - medications (List<MedicationSchedule>): Medication list used for retrieval, selection, ordering, or display.
class _DashboardPendingSlot {
  final String slotKey;
  final DateTime scheduledAt;
  final MedicationAlarm alarm;
  final List<MedicationSchedule> medications;

  // Function Name: _DashboardPendingSlot
  // Description: Combines the supplied values for a pending dashboard slot and its medication count in a _DashboardPendingSlot instance.
  // Parameters:
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // - scheduledAt (DateTime): Scheduled date and time for the dose slot.
  // - alarm (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
  // - medications (List<MedicationSchedule>): Medication list used for retrieval, selection, ordering, or display.
  // Returns: Initialized _DashboardPendingSlot instance.
  const _DashboardPendingSlot({
    required this.slotKey,
    required this.scheduledAt,
    required this.alarm,
    required this.medications,
  });
}
