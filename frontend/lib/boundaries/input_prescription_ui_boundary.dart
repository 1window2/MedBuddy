// File Name: input_prescription_ui_boundary.dart
// Role: UI boundaries and helpers for the home medication dashboard and medication input entry points.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'medication_search_ui_boundary.dart';
import '../widgets/medbuddy_wordmark.dart';

import 'medication_capture_options_ui_boundary.dart';
import 'check_saved_medication_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/home_medication_preview.dart';
import '../widgets/home_medication_slot_pager.dart';
import '../widgets/keep_words_text.dart';

// 파일명: input_prescription_ui_boundary.dart
// 역할: MedBuddy 홈 화면과 처방전 입력 진입점을 구성한다.

// 클래스명: InputPrescriptionUI
// 역할: 홈의 복약 현황과 약 등록·조회 진입 화면.
// 주요 책임: 사용자 언어·글씨 설정을 적용하고 처방전 카메라·갤러리 입력 등 주요 기능으로 연결한다.
// 속성: userSetting: 표시 설정; todayMedicationScheduleList: 오늘 일정; medicationReminderSettings: 시간대별 알림; 콜백: 기능별 진입 동작.
class InputPrescriptionUI extends StatelessWidget {
  final UserSetting userSetting;
  final List<MedicationSchedule> todayMedicationScheduleList;
  final Map<String, MedicationAlarm> medicationReminderSettings;
  final int todayMedicationCompletedCount;
  final int todayMedicationTotalCount;
  final bool isTodayScheduleLoading;
  final bool hasTodayScheduleLoadError;
  // 본인 복용약이 없는 보호자에게만 전달하는 가족 복약 현황이다.
  final Widget? caregiverSummary;
  final Widget? caregiverScheduleHint;
  final DateTime Function()? nowProvider;
  final ValueChanged<PillCaptureMode>? onPillIdentificationRequested;
  final VoidCallback? onManualMedicationRequested;
  // 약 등록 화면의 사진으로 복용 기록. null이면 그 버튼을 보이지 않는다.
  final void Function(BuildContext pageContext)? onPhotoDoseRequested;
  final Future<void> Function(BuildContext, PrescriptionImageSource)?
  onRegistrationSourceRequested;
  final VoidCallback? onTodayScheduleRequested;
  final Future<bool> Function(String slotKey, bool completed)?
  onMedicationSlotStatusRequested;
  final bool isNextMedicationCompletionLoading;
  final VoidCallback? onNearbyPharmacyRequested;
  final VoidCallback? onHealthRecommendationRequested;
  final VoidCallback? onUserSettingRequested;
  final VoidCallback? onNotificationsRequested;
  final VoidCallback? onFeatureSearchRequested;
  final int unreadNotificationCount;

  // 함수이름: InputPrescriptionUI
  // 함수역할: 본인 또는 가족 복약 현황과 약 등록·검색·알림함 진입 동작을 홈 화면에 연결한다.
  // 매개변수:
  // - key (Key?): 홈 위젯 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 표시 설정.
  // - todayMedicationScheduleList (List<MedicationSchedule>): 오늘 표시할 복약 일정.
  // - medicationReminderSettings (Map<String, MedicationAlarm>): 시간대별 알림 설정.
  // - todayMedicationCompletedCount, todayMedicationTotalCount (int): 완료·전체 복용 횟수.
  // - isTodayScheduleLoading, hasTodayScheduleLoadError (bool): 조회 진행과 실패 여부. 실패를 약 없음으로 표시하지 않는다.
  // - caregiverSummary, caregiverScheduleHint (Widget?): 본인 복약 요약을 대신할 가족 현황과 대시보드 아래에 추가할 가족 일정 안내.
  // - nowProvider (DateTime Function()?): 일정 판단용 시계. 생략하면 기기 시각을 사용한다.
  // - onPillIdentificationRequested (ValueChanged<PillCaptureMode>?): 선택한 촬영 방식으로 알약 식별을 여는 동작.
  // - onManualMedicationRequested (VoidCallback?): 직접 약 입력을 여는 동작.
  // - onRegistrationSourceRequested (Future<void> Function(BuildContext, PrescriptionImageSource)?): 등록 화면의 문맥과 선택한 사진 출처를 받아 등록 흐름을 진행하는 동작.
  // - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 진입 동작.
  // - onMedicationSlotStatusRequested (Future<bool> Function(String, bool)?): 시간대와 완료 여부를 저장하고 성공 여부를 반환하는 동작.
  // - isNextMedicationCompletionLoading (bool): 다음 복용 완료 처리가 진행 중인지 여부.
  // - onNearbyPharmacyRequested, onHealthRecommendationRequested, onUserSettingRequested (VoidCallback?): 주변 병원·약국 선택, 건강 안내, 사용자 설정 진입 동작.
  // - onNotificationsRequested, onFeatureSearchRequested (VoidCallback?): 알림함과 기능 검색 진입 동작.
  // - unreadNotificationCount (int): 알림함 버튼에 표시할 미확인 알림 수이며 기본값은 0이다.
  // 반환값: 현황과 진입 동작이 연결된 홈 화면. 생성 시 조회·저장을 실행하지 않는다.
  const InputPrescriptionUI({
    super.key,
    required this.userSetting,
    this.todayMedicationScheduleList = const [],
    this.medicationReminderSettings = const {},
    this.todayMedicationCompletedCount = 0,
    this.todayMedicationTotalCount = 0,
    this.isTodayScheduleLoading = false,
    this.hasTodayScheduleLoadError = false,
    this.caregiverSummary,
    this.caregiverScheduleHint,
    this.nowProvider,
    required this.onPillIdentificationRequested,
    this.onManualMedicationRequested,
    this.onPhotoDoseRequested,
    this.onRegistrationSourceRequested,
    required this.onTodayScheduleRequested,
    this.onMedicationSlotStatusRequested,
    this.isNextMedicationCompletionLoading = false,
    this.onNearbyPharmacyRequested,
    required this.onHealthRecommendationRequested,
    required this.onUserSettingRequested,
    this.onNotificationsRequested,
    this.onFeatureSearchRequested,
    this.unreadNotificationCount = 0,
  });

  // Function Name: build
  // Description: Displays medication progress and quick actions with content-sized cards that retain descriptions at large text scales.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final text = _HomeText(userSetting.language);

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _HomeHeader(
              text: text,
              onNotificationsPressed: onNotificationsRequested,
              onSearchPressed: onFeatureSearchRequested,
              unreadCount: unreadNotificationCount,
            ),
            Expanded(
              child: LayoutBuilder(
                // 함수이름: 홈 스크롤 영역 builder
                // 함수역할: 화면 너비에 맞춰 여백을 정한다. 큰 글씨에서는 기능 버튼이 내용 높이만큼 자란다.
                // 매개변수: context (BuildContext), viewportConstraints (BoxConstraints): 화면 문맥과 사용 가능한 크기.
                // 반환값: 복약 현황과 기능 카드가 배치된 스크롤 영역.
                builder: (context, viewportConstraints) {
                  final useCompactDashboard =
                      viewportConstraints.maxWidth >= 350;
                  // 기본 글씨의 흔한 휴대폰에서 보호자 안내까지 스크롤 없이 보이도록 세로 간격을 줄인다.
                  final dashboardActionSpacing = useCompactDashboard
                      ? viewportConstraints.maxHeight >= 600
                            ? 14.0
                            : 12.0
                      : 20.0;

                  return SingleChildScrollView(
                    key: const ValueKey('homeDashboardScrollView'),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      useCompactDashboard ? 10 : 16,
                      20,
                      useCompactDashboard ? 8 : 32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: MedBuddySpacing.contentMaxWidth,
                        ),
                        child: _HomeFillLayout(
                          availableHeight: math.max(
                            0,
                            viewportConstraints.maxHeight -
                                (useCompactDashboard ? 18 : 48),
                          ),
                          sectionGap: dashboardActionSpacing,
                          rowGap: 12,
                          top:
                              caregiverSummary ??
                              _HomeEncouragementPanel(
                                userSetting: userSetting,
                                schedules: todayMedicationScheduleList,
                                reminderSettings: medicationReminderSettings,
                                completedCount: todayMedicationCompletedCount,
                                totalCount: todayMedicationTotalCount,
                                isLoading: isTodayScheduleLoading,
                                hasError: hasTodayScheduleLoadError,
                                nowProvider: nowProvider,
                                compact: useCompactDashboard,
                                onTap: onTodayScheduleRequested,
                                onStatusUpdateRequested:
                                    onMedicationSlotStatusRequested,
                                isCompletionLoading:
                                    isNextMedicationCompletionLoading,
                              ),
                          rows: _homeActionRows(
                            narrow: viewportConstraints.maxWidth < 350,
                            tiles: [
                              _HomeTileData(
                                key: const ValueKey(
                                  'homeMedicationRegisterCard',
                                ),
                                icon: Icons.medication_outlined,
                                title: text.medicationRegister,
                                hint: text.medicationRegisterHint,
                                tone: _HomeActionTone.primary,
                                onTap: () => _openRegistration(context),
                              ),
                              _HomeTileData(
                                key: const ValueKey('homeMedicationManageCard'),
                                icon: Icons.inventory_2_outlined,
                                title: text.medicationManage,
                                hint: text.medicationManageHint,
                                tone: _HomeActionTone.primary,
                                onTap: () => _openMedicationManagement(context),
                              ),
                              _HomeTileData(
                                key: const ValueKey('homeMedicationSearchCard'),
                                icon: Icons.manage_search_rounded,
                                title: text.medicationSearch,
                                hint: text.medicationSearchHint,
                                tone: _HomeActionTone.primary,
                                onTap: () => _openMedicationSearch(context),
                              ),
                              _HomeTileData(
                                key: const ValueKey(
                                  'homeHealthRecommendationCard',
                                ),
                                icon: Icons.monitor_heart_outlined,
                                title: text.healthRecommendation,
                                hint: text.healthRecommendationSubtitle,
                                tone: _HomeActionTone.mint,
                                onTap: onHealthRecommendationRequested,
                              ),
                              _HomeTileData(
                                key: const ValueKey('homeNearbyPharmacyCard'),
                                icon: Icons.map_outlined,
                                title: text.nearbyPharmacy,
                                hint: text.nearbyPharmacySubtitle,
                                tone: _HomeActionTone.lavender,
                                onTap: onNearbyPharmacyRequested,
                              ),
                              _HomeTileData(
                                key: const ValueKey('homeUserSettingsCard'),
                                icon: Icons.settings_outlined,
                                title: text.userSettings,
                                hint: text.userSettingsSubtitle,
                                tone: _HomeActionTone.butter,
                                onTap: onUserSettingRequested,
                              ),
                            ],
                          ),
                          trailing: caregiverScheduleHint,
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

  // 함수이름: _openRegistration
  // 함수역할: 약 등록 화면을 연다. 홈에서 열 때만 사진으로 복용 기록을 함께 보인다.
  // 매개변수: context (BuildContext): 화면 이동 위치.
  // 반환값: 등록 화면이 닫히면 완료되는 Future<void>.
  Future<void> _openRegistration(BuildContext context) =>
      showMedicationCaptureTaskOptions(
        context: context,
        userSetting: userSetting,
        includePhotoDose: onPhotoDoseRequested != null,
        onTaskSelected: (pageContext, task) async {
          switch (task) {
            case MedicationCaptureTask.pills:
              onPillIdentificationRequested?.call(PillCaptureMode.singlePhoto);
            case MedicationCaptureTask.manual:
              onManualMedicationRequested?.call();
            case MedicationCaptureTask.photoDose:
              onPhotoDoseRequested?.call(pageContext);
          }
        },
        onSourceSelected: (pageContext, source) async =>
            onRegistrationSourceRequested?.call(pageContext, source),
      );

  // 함수이름: _openMedicationManagement
  // 함수역할: 저장한 약 관리 화면을 연다.
  // 매개변수: context (BuildContext): 화면 이동 위치.
  // 반환값: 화면이 닫히면 완료.
  Future<void> _openMedicationManagement(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const CheckSavedMedicationUI()),
      );

  // 함수이름: _openMedicationSearch
  // 함수역할: 약 이름 검색 화면을 연다.
  // 매개변수: context (BuildContext): 화면 이동 위치.
  // 반환값: 화면이 닫히면 완료.
  Future<void> _openMedicationSearch(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MedicationSearchUI(userSetting: userSetting),
        ),
      );
}

// Class Name: _HomeHeader
// Role: Home heading with feature search and unread-notification access.
// Responsibilities: Keeps the title separate from optional action callbacks and unread count.
// Attributes: text (_HomeText): labels; onNotificationsPressed/onSearchPressed (VoidCallback?): actions; unreadCount (int): unread total.
class _HomeHeader extends StatelessWidget {
  final _HomeText text;
  final VoidCallback? onNotificationsPressed;
  final VoidCallback? onSearchPressed;
  final int unreadCount;

  // 함수이름: _HomeHeader
  // 함수역할: 홈 제목과 알림함 상단 콘텐츠를 초기화한다.
  // 매개변수:
  // - text (_HomeText): 해당 화면 구역의 언어별 표시 문구.
  // - onNotificationsPressed (VoidCallback?): 알림함을 여는 콜백.
  // - unreadCount (int): 아직 확인하지 않은 알림 개수.
  // - onSearchPressed (VoidCallback?): 기능 검색을 여는 동작. null이면 검색 버튼을 표시하지 않는다.
  // 반환값: 입력 설정이 반영된 _HomeHeader 인스턴스.
  const _HomeHeader({
    required this.text,
    required this.onNotificationsPressed,
    required this.onSearchPressed,
    required this.unreadCount,
  });

  // Function Name: build
  // Description: Renders the home heading and supporting top-bar content from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the home heading and supporting top-bar content.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MedBuddyColors.pageBackground,
      padding: EdgeInsets.fromLTRB(
        22,
        MediaQuery.of(context).padding.top + 24,
        20,
        10,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MedBuddySpacing.contentMaxWidth,
          ),
          child: Row(
            children: [
              const Expanded(
                child: MedBuddyWordmark(key: ValueKey('homeBrandLogo')),
              ),
              const SizedBox(width: 8),
              if (onSearchPressed != null) ...[
                IconButton(
                  key: const ValueKey('homeFeatureSearchButton'),
                  tooltip: text.isEnglish ? 'Find a feature' : '기능 찾기',
                  onPressed: onSearchPressed,
                  style: IconButton.styleFrom(
                    foregroundColor: MedBuddyColors.primaryDark,
                    minimumSize: const Size.square(48),
                  ),
                  icon: const Icon(Icons.search, size: 26),
                ),
                const SizedBox(width: 4),
              ],
              Badge(
                isLabelVisible: unreadCount > 0,
                label: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  textScaler: TextScaler.noScaling,
                ),
                child: IconButton.filledTonal(
                  key: const ValueKey('homeNotificationsButton'),
                  tooltip: text.isEnglish
                      ? 'Notifications, $unreadCount unread'
                      : '알림, 안 읽은 알림 $unreadCount개',
                  onPressed: onNotificationsPressed,
                  style: IconButton.styleFrom(
                    backgroundColor: MedBuddyColors.mint,
                    foregroundColor: MedBuddyColors.primaryDark,
                    minimumSize: const Size.square(48),
                  ),
                  icon: const Icon(Icons.notifications_none_outlined, size: 24),
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
// Role: Color variants for primary and secondary home actions.
// Responsibilities: Distinguishes the filled primary action from lightly accented quick actions.
// Attributes: primary/mint/lavender/butter: visual variants.
enum _HomeActionTone { primary, mint, lavender, butter }

// 클래스명: _HomeTileData
// 역할: 홈 기능 버튼 하나의 내용. 설명(hint)은 화면에 보이지 않고 화면 읽기로만 읽는다.
class _HomeTileData {
  final Key key;
  final IconData icon;
  final String title;
  final String hint;
  final _HomeActionTone tone;
  final VoidCallback? onTap;

  const _HomeTileData({
    required this.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.tone,
    required this.onTap,
  });
}

// 함수이름: _homeActionRows
// 함수역할: 홈 기능 버튼을 줄로 묶는다. 약 등록은 맨 위 가로 전체, 그 아래 두 줄은 두 개씩, 환경설정은 맨 아래
//   가로 전체다. 좁은 화면은 한 줄에 하나씩 놓는다. 모든 줄은 _HomeFillLayout이 같은 높이로 맞춘다.
// 매개변수: narrow (bool): 좁은 화면 여부; tiles: 약 등록·관리·검색, 건강, 병원·약국, 설정 순.
// 반환값: 줄 위젯 목록.
List<Widget> _homeActionRows({
  required bool narrow,
  required List<_HomeTileData> tiles,
}) {
  if (narrow) {
    return [for (final tile in tiles) _HomeTile(data: tile, chevron: true)];
  }
  Widget pair(_HomeTileData left, _HomeTileData right) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _HomeTile(data: left)),
      const SizedBox(width: _homeTileGap),
      Expanded(child: _HomeTile(data: right)),
    ],
  );
  return [
    _HomeTile(data: tiles[0], chevron: true),
    pair(tiles[1], tiles[2]),
    pair(tiles[3], tiles[4]),
    _HomeTile(data: tiles[5], chevron: true),
  ];
}

// 버튼 사이 가로·세로 간격. 줄 사이 간격(rowGap)과 같아야 한다.
const double _homeTileGap = 12;

// 클래스명: _HomeFillLayout
// 역할: 위쪽 복약 현황 아래에 기능 버튼 줄을 같은 높이로 놓는다. 화면에 남는 높이를 줄마다 똑같이 나눠 쓰되
//   한 줄은 76~112dp로 둔다. 글씨가 커서 내용이 더 높으면 가장 높은 줄에 맞추고 화면이 스크롤된다.
// 속성: top: 복약 현황; rows: 버튼 줄; trailing: 아래 안내(선택); availableHeight: 스크롤 영역 높이;
//   sectionGap: 현황과 버튼 사이; rowGap: 버튼 줄 사이.
class _HomeFillLayout extends MultiChildRenderObjectWidget {
  final double availableHeight;
  final double sectionGap;
  final double rowGap;
  final int rowCount;
  final bool hasTrailing;

  _HomeFillLayout({
    required Widget top,
    required List<Widget> rows,
    Widget? trailing,
    required this.availableHeight,
    required this.sectionGap,
    required this.rowGap,
  }) : rowCount = rows.length,
       hasTrailing = trailing != null,
       super(children: [top, ...rows, ?trailing]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHomeFill(
    availableHeight: availableHeight,
    sectionGap: sectionGap,
    rowGap: rowGap,
    rowCount: rowCount,
    hasTrailing: hasTrailing,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderHomeFill renderObject) {
    renderObject
      ..availableHeight = availableHeight
      ..sectionGap = sectionGap
      ..rowGap = rowGap
      ..rowCount = rowCount
      ..hasTrailing = hasTrailing;
  }
}

class _HomeFillParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHomeFill extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HomeFillParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HomeFillParentData> {
  static const double minRowHeight = 76;
  static const double maxRowHeight = 112;
  static const double trailingGap = 8;

  _RenderHomeFill({
    required double availableHeight,
    required double sectionGap,
    required double rowGap,
    required int rowCount,
    required bool hasTrailing,
  }) : _availableHeight = availableHeight,
       _sectionGap = sectionGap,
       _rowGap = rowGap,
       _rowCount = rowCount,
       _hasTrailing = hasTrailing;

  double _availableHeight;
  set availableHeight(double value) {
    if (value == _availableHeight) return;
    _availableHeight = value;
    markNeedsLayout();
  }

  double _sectionGap;
  set sectionGap(double value) {
    if (value == _sectionGap) return;
    _sectionGap = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) return;
    _rowGap = value;
    markNeedsLayout();
  }

  int _rowCount;
  set rowCount(int value) {
    if (value == _rowCount) return;
    _rowCount = value;
    markNeedsLayout();
  }

  bool _hasTrailing;
  set hasTrailing(bool value) {
    if (value == _hasTrailing) return;
    _hasTrailing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HomeFillParentData) {
      child.parentData = _HomeFillParentData();
    }
  }

  List<RenderBox> get _children {
    final result = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      result.add(child);
      child = childAfter(child);
    }
    return result;
  }

  double _contentRowHeight(List<RenderBox> rows, double width) => rows.fold(
    minRowHeight,
    (height, row) => math.max(height, row.getMaxIntrinsicHeight(width)),
  );

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(
    0,
    (width, child) => math.max(width, child.getMinIntrinsicWidth(height)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(
    0,
    (width, child) => math.max(width, child.getMaxIntrinsicWidth(height)),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _measure(width).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _measure(width).height;

  Size _measure(double width) {
    final children = _children;
    final rows = children.sublist(1, 1 + _rowCount);
    final top = children.first.getMaxIntrinsicHeight(width);
    final trailing = _hasTrailing
        ? children.last.getMaxIntrinsicHeight(width) + trailingGap
        : 0.0;
    final rowHeight = _contentRowHeight(rows, width);
    return Size(
      width,
      top +
          _sectionGap +
          rowHeight * _rowCount +
          _rowGap * math.max(0, _rowCount - 1) +
          trailing,
    );
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final children = _children;
    final top = children.first;
    final rows = children.sublist(1, 1 + _rowCount);
    final trailing = _hasTrailing ? children.last : null;
    top.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    trailing?.layout(
      BoxConstraints.tightFor(width: width),
      parentUsesSize: true,
    );
    final trailingHeight = trailing == null
        ? 0.0
        : trailing.size.height + trailingGap;
    final gaps = _sectionGap + _rowGap * math.max(0, _rowCount - 1);
    final share =
        (_availableHeight - top.size.height - trailingHeight - gaps) /
        math.max(1, _rowCount);
    final rowHeight = math.max(
      share.clamp(minRowHeight, maxRowHeight).toDouble(),
      _contentRowHeight(rows, width),
    );
    var y = 0.0;
    (top.parentData! as _HomeFillParentData).offset = Offset.zero;
    y += top.size.height + _sectionGap;
    for (var i = 0; i < rows.length; i++) {
      rows[i].layout(BoxConstraints.tightFor(width: width, height: rowHeight));
      (rows[i].parentData! as _HomeFillParentData).offset = Offset(0, y);
      y += rowHeight + (i == rows.length - 1 ? 0 : _rowGap);
    }
    if (trailing != null) {
      y += trailingGap;
      (trailing.parentData! as _HomeFillParentData).offset = Offset(0, y);
      y += trailing.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

// 클래스명: _HomeTile
// 역할: 큰 아이콘(왼쪽)과 이름(오른쪽)만 있는 홈 기능 버튼.
// 속성: data: 내용; chevron: 오른쪽 화살표 표시. 아이콘 칸과 글씨 크기는 모든 버튼이 같다.
class _HomeTile extends StatelessWidget {
  static const double iconSize = 54;
  static const double titleSize = 19;

  final _HomeTileData data;
  final bool chevron;

  const _HomeTile({required this.data, this.chevron = false});

  @override
  Widget build(BuildContext context) {
    final primary = data.tone == _HomeActionTone.primary;
    final foreground = primary ? Colors.white : MedBuddyColors.textStrong;
    final accent = switch (data.tone) {
      _HomeActionTone.primary => Colors.white,
      _HomeActionTone.mint => MedBuddyColors.primaryDark,
      _HomeActionTone.lavender => MedBuddyColors.infoBlue,
      _HomeActionTone.butter => MedBuddyColors.reminderAccent,
    };
    return Semantics(
      button: true,
      hint: data.hint,
      child: Material(
        color: primary ? MedBuddyColors.primary : MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.largeCard,
        child: InkWell(
          key: data.key,
          borderRadius: MedBuddyRadii.largeCard,
          onTap: data.onTap,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(14, 10, chevron ? 10 : 14, 10),
            decoration: BoxDecoration(
              borderRadius: MedBuddyRadii.largeCard,
              border: Border.all(
                color: primary
                    ? MedBuddyColors.primary
                    : MedBuddyColors.cardBorder,
              ),
            ),
            child: Row(
              children: [
                _ActionIcon(
                  icon: data.icon,
                  tone: data.tone,
                  color: accent,
                  size: iconSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KeepWordsText(
                    data.title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: titleSize,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (chevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accent.withValues(alpha: 0.8),
                    size: 30,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Class Name: _ActionIcon
// Role: Represents the color-coded icon for a home quick action.
// Responsibilities:
// - Composes the color-coded icon for a home quick action using the display values and actions supplied by its parent.
// Attributes:
// - icon (IconData): Icon shown in normal or selected state.
// - tone (_HomeActionTone): Primary fill or icon tint for the home action.
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
  // - tone (_HomeActionTone): Primary fill or icon tint for the home action.
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
        color: switch (tone) {
          _HomeActionTone.primary => Colors.white.withValues(alpha: 0.16),
          _HomeActionTone.mint => MedBuddyColors.successSurface,
          _HomeActionTone.lavender => MedBuddyColors.lavenderSurface,
          _HomeActionTone.butter => MedBuddyColors.butterSurface,
        },
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.62),
    );
  }
}

// 클래스명: _HomeText
// 역할: 홈 복약 현황과 입력 진입점의 현지화 문구.
// 주요 책임: 선택 언어로 기능명·설명·복약 현황 안내를 제공한다.
// 속성: language (String): 표시 언어 코드.
class _HomeText {
  final String language;

  // 함수이름: _HomeText
  // 함수역할: 홈 대시보드의 복약 요약과 약 정보 입력 진입에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _HomeText 인스턴스.
  const _HomeText(this.language);

  // Function Name: isEnglish
  // Description: Applies the shared English-language rule to home labels.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: userSettings
  // 함수역할: 환경설정 카드 제목을 번역한다. 매개변수: 없음. 반환값: 제목.
  String get userSettings => isEnglish ? 'Settings' : '환경설정';
  // Function Name: userSettingsSubtitle
  // Description: Describes the preferences available from the user-settings action.
  // Parameters: None.
  // Returns: The localized settings subtitle.
  String get userSettingsSubtitle => isEnglish
      ? 'Adjust text, language and notifications'
      : '글자 크기·언어·알림을 설정해요';
  // 함수이름: medicationRegister
  // 함수역할: 약 등록 버튼 이름과 화면 읽기 설명을 제공한다.
  // 매개변수: 없음. 반환값: 문구.
  String get medicationRegister => isEnglish ? 'Add medication' : '약 등록';
  String get medicationRegisterHint => isEnglish
      ? 'Add a medicine from a prescription, a pill photo or by hand, or record a dose from a photo.'
      : '약봉투·알약 사진·직접 입력으로 약을 등록하거나, 사진으로 복용을 기록해요.';
  // 함수이름: medicationManage
  // 함수역할: 약 관리 버튼 이름과 화면 읽기 설명을 제공한다.
  // 매개변수: 없음. 반환값: 문구.
  String get medicationManage => isEnglish ? 'My medications' : '약 관리';
  String get medicationManageHint => isEnglish
      ? 'View and manage saved medications.'
      : '등록한 약과 복용 기간을 확인하고 관리해요.';
  // 함수이름: medicationSearch
  // 함수역할: 약 검색 버튼 이름과 화면 읽기 설명을 제공한다.
  // 매개변수: 없음. 반환값: 문구.
  String get medicationSearch => isEnglish ? 'Find medication' : '약 검색';
  String get medicationSearchHint => isEnglish
      ? 'Look up medication information by name.'
      : '약 이름으로 약품 정보를 찾아요.';
  // 함수이름: prescriptionAnalysis
  // 함수역할: 처방전·알약 식별·직접 등록을 포함하는 홈 진입점의 이름을 번역한다.
  // 매개변수: 없음. 반환값: 현재 언어의 카드 제목.
  String get prescriptionAnalysis =>
      isEnglish ? 'Add or manage medication' : '약 등록·관리';
  // 함수이름: prescriptionAnalysisSubtitle
  // 함수역할: 약 정보 입력과 식별 방법을 카드 설명으로 안내한다.
  // 매개변수: 없음. 반환값: 현재 언어의 카드 설명.
  String get prescriptionAnalysisSubtitle =>
      isEnglish ? 'Add or manage your medications' : '약을 등록하고 저장한 약을 관리해요';
  // Function Name: healthRecommendation
  // Description: Provides localized wording for "Health Recommendations" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get healthRecommendation =>
      isEnglish ? 'Health tips' : '건강 관리 추천';
  // Function Name: healthRecommendationSubtitle
  // Description: Provides localized wording for "Review food and activity guidance for your medications" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get healthRecommendationSubtitle => isEnglish
      ? 'Review food and activity guidance for your medications'
      : '복용 중인 약에 맞는 식사와 활동 팁을 확인해요';
  // 함수이름: nearbyPharmacy
  // 함수역할: 병원·약국을 함께 찾는 홈 진입점의 제목을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nearbyPharmacy =>
      isEnglish ? 'Hospitals & pharmacies' : '근처 운영 병원·약국';
  // 함수이름: nearbyPharmacySubtitle
  // 함수역할: 2×2 기능 카드에서 주변 병원·약국의 운영시간 조회를 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get nearbyPharmacySubtitle => isEnglish
      ? 'Check nearby hospital and pharmacy hours'
      : '가까운 병원·약국의 운영시간을 확인해요';
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
  final bool hasError;
  final bool compact;
  final DateTime Function()? nowProvider;
  final VoidCallback? onTap;
  final Future<bool> Function(String slotKey, bool completed)?
  onStatusUpdateRequested;
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
  // - hasError (bool): Whether the schedule could not be loaded and the status is unknown.
  // - compact (bool): Whether compact card or header layout is used.
  // - nowProvider (DateTime Function()?): Clock function; the device's current time is used when omitted.
  // - onTap (VoidCallback?): Callback executing the item's documented primary action.
  // - onStatusUpdateRequested (Future<bool> Function(String, bool)?): Saves completion or cancellation of the selected dose slot.
  // - isCompletionLoading (bool): Whether the associated save, analysis, or medication update is in progress.
  // Returns: Initialized _HomeEncouragementPanel instance.
  const _HomeEncouragementPanel({
    required this.userSetting,
    required this.schedules,
    required this.reminderSettings,
    required this.completedCount,
    required this.totalCount,
    required this.isLoading,
    this.hasError = false,
    this.compact = false,
    this.nowProvider,
    this.onTap,
    this.onStatusUpdateRequested,
    this.isCompletionLoading = false,
  });

  // Function Name: build
  // Description: Shows dose progress and per-slot summaries while tracking the selected slot and allowing the panel to grow with content.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final isEnglish = userSetting.isEnglish;
    final dashboard = _HomeDashboardSummary.from(
      schedules: schedules,
      reminderSettings: reminderSettings,
      completedCount: completedCount,
      totalCount: totalCount,
      isLoading: isLoading,
      isEnglish: isEnglish,
      nowProvider: nowProvider,
    );

    return HomeMedicationPreview(
      key: const ValueKey('homeEncouragementPanel'),
      title: dashboard.statusMessage,
      progressTitle: isEnglish ? 'Today\'s progress' : '오늘의 복약 진행률',
      progressLabel: dashboard.progressLabel,
      progress: dashboard.progress,
      scheduleTitle: '',
      scheduleDescription: '',
      hasPendingMedication: dashboard.nextSlotKey != null,
      compact: compact,
      onTap: onTap,
      scheduleContent: HomeMedicationSlotPager(
        schedules: schedules,
        reminderSettings: reminderSettings,
        isEnglish: isEnglish,
        isLoading: isLoading,
        hasError: hasError,
        initialSlotKey: dashboard.nextSlotKey,
        compact: compact,
        onStatusUpdateRequested: onStatusUpdateRequested,
        isCompletionLoading: isCompletionLoading,
        onDetailsRequested: onTap,
        timeFormatter: userSetting.formatTime,
      ),
    );
  }
}

// Class Name: _HomeDashboardSummary
// Role: Represents home summary text, the next dose slot, and batch completion state.
// Responsibilities:
// - Clamps completed doses to the total and selects the next upcoming slot or latest overdue slot.
// Attributes:
// - progress (double): Completion fraction from zero to one.
// - progressLabel (String): Text showing completed and total counts.
// - statusMessage (String): Visible wording for the current result, error, or state.
// - nextSlotKey (String?): Key identifying morning, lunch, evening, or bedtime.
class _HomeDashboardSummary {
  static const _slotOrder = ['morning', 'lunch', 'evening', 'bedtime'];

  final double progress;
  final String progressLabel;
  final String statusMessage;
  final String? nextSlotKey;

  // Function Name: _HomeDashboardSummary
  // Description: Combines the supplied values for home summary text, the next dose slot, and batch completion state in a _HomeDashboardSummary instance.
  // Parameters:
  // - progress (double): Completion fraction from zero to one.
  // - progressLabel (String): Text showing completed and total counts.
  // - statusMessage (String): Visible wording for the current result, error, or state.
  // - nextSlotKey (String?): Key identifying morning, lunch, evening, or bedtime.
  // Returns: Initialized _HomeDashboardSummary instance.
  const _HomeDashboardSummary({
    required this.progress,
    required this.progressLabel,
    required this.statusMessage,
    required this.nextSlotKey,
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
        nextSlotKey: null,
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
      final hasPendingSchedule = schedules.any(
        // 함수이름: initializer.any callback
        // 함수역할: 홈 요약 문구·다음 시간대·일괄 완료 상태에 대해 `schedule.slotKeys.contains(slotKey) && !schedule.isSlotCompleted(slotKey)` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        (schedule) =>
            schedule.slotKeys.contains(slotKey) &&
            !schedule.isSlotCompleted(slotKey),
      );
      if (!hasPendingSchedule) {
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
        nextSlotKey: null,
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
    final statusMessage = isPastDue
        ? (isEnglish
              ? 'You have a missed medication to check'
              : '미복용한 약을 확인해주세요')
        : (isEnglish
              ? 'You are keeping up with your medication'
              : '오늘도 복약을 꾸준히 이어가고 있어요');

    return _HomeDashboardSummary(
      progress: progress,
      progressLabel: progressLabel,
      statusMessage: statusMessage,
      nextSlotKey: nextSlot.slotKey,
    );
  }
}

// Class Name: _DashboardPendingSlot
// Role: Represents a pending dashboard slot and its scheduled time.
// Responsibilities:
// - Groups the supplied field values for a pending dashboard slot and its scheduled time in a single object.
// Attributes:
// - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
// - scheduledAt (DateTime): Scheduled date and time for the dose slot.
class _DashboardPendingSlot {
  final String slotKey;
  final DateTime scheduledAt;

  // Function Name: _DashboardPendingSlot
  // Description: Combines the supplied values for a pending dashboard slot and its scheduled time in a _DashboardPendingSlot instance.
  // Parameters:
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // - scheduledAt (DateTime): Scheduled date and time for the dose slot.
  // Returns: Initialized _DashboardPendingSlot instance.
  const _DashboardPendingSlot({
    required this.slotKey,
    required this.scheduledAt,
  });
}
