// 파일명: feature_search_ui_boundary.dart
// 역할: 주요 기능과 자연스러운 검색 표현의 결과를 보여주고 선택한 목적지만 반환한다.
import 'package:flutter/material.dart';
import '../controls/find_app_feature_control.dart';
import '../entities/feature_search_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/keep_words_text.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medbuddy_search_field.dart';

// Class Name: FeatureSearchUI
// Role: Searches app destinations without fetching account data.
// Responsibilities: Filters unsupported device features and delegates the chosen destination to its parent.
// Attributes: isEnglish/widgetSupported (bool): language/device support; onFeatureSelected (Future<void> Function(BuildContext,AppFeature)): destination action.
class FeatureSearchUI extends StatefulWidget {
  final bool isEnglish;
  final bool widgetSupported;
  final Future<void> Function(BuildContext, AppFeature) onFeatureSelected;

  // Function Name: FeatureSearchUI
  // Description: Binds the display language, device support and asynchronous destination action.
  // Parameters: key (Key?): widget identity; isEnglish/widgetSupported (bool): language/support; onFeatureSelected (Future<void> Function(BuildContext,AppFeature)): selection action.
  // Returns: New FeatureSearchUI.
  const FeatureSearchUI({
    super.key,
    this.isEnglish = false,
    this.widgetSupported = true,
    required this.onFeatureSelected,
  });

  // 함수이름: createState
  // 함수역할: 현재 화면에서만 검색어와 기능 열기 잠금을 보관할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _FeatureSearchUIState.
  @override
  State<FeatureSearchUI> createState() => _FeatureSearchUIState();
}

// 클래스명: _FeatureSearchUIState
// 역할: 검색어를 화면 수명 동안만 보관하고 기능 선택의 중복 실행을 막는다.
// 주요 책임: 검색어가 없으면 범주별 기능을, 있으면 일치 결과를 표시한다.
// 속성: _query (TextEditingController): 검색어; _openingFeature (bool): 선택 처리 중.
class _FeatureSearchUIState extends State<FeatureSearchUI> {
  final _query = TextEditingController();
  bool _openingFeature = false;
  // 함수이름: _english
  // 함수역할: 부모 화면의 언어 설정을 읽는다.
  // 매개변수: 없음.
  // 반환값: 영어이면 true.
  bool get _english => widget.isEnglish;

  // 함수이름: dispose
  // 함수역할: 화면에만 보관하던 검색 입력 제어기를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 지원되는 기능을 검색하거나 범주별로 나누어 표시하며 빈 검색 결과를 구분한다.
  // 매개변수: context (BuildContext): 표시·선택 명령 위치.
  // 반환값: 기능 검색 Scaffold.
  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.text.trim().isNotEmpty;
    final available = FindAppFeature.entries.where(
      (entry) =>
          widget.widgetSupported || entry.feature != AppFeature.homeWidget,
    );
    final results = hasQuery
        ? FindAppFeature.search(
            _query.text,
            widgetSupported: widget.widgetSupported,
          )
        : available.toList(growable: false);
    final categories = hasQuery
        ? results.map((entry) => _category(entry.feature)).toSet().toList()
        : _FeatureCategory.values;
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MedBuddyPageHeader(
              title: _english ? 'Find a feature' : '기능 찾기',
              subtitle: _english
                  ? 'Find a feature and go straight to it.'
                  : '원하는 기능을 검색하고 바로 이동합니다.',
              onBackRequested: () => Navigator.pop(context),
              backTooltip: _english ? 'Back' : '뒤로',
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: MedBuddySpacing.contentMaxWidth,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: MedBuddySearchField(
                          inputKey: const Key('featureSearchInput'),
                          clearKey: const Key('featureSearchClear'),
                          controller: _query,
                          isEnglish: _english,
                          onChanged: () => setState(() {}),
                          label: _english ? 'Feature search' : '기능 검색',
                          hint: _english
                              ? 'Bigger text, send records'
                              : '글씨 크게, 먹은 기록 보내기',
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: ListView(
                            key: const Key('featureSearchPanel'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.zero,
                            children: [
                              if (hasQuery && results.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 32,
                                  ),
                                  child: KeepWordsText(
                                    _english
                                        ? 'No matching features'
                                        : '검색 결과가 없어요',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: MedBuddyColors.textMuted,
                                    ),
                                  ),
                                ),
                              for (final category in categories)
                                _categoryPanel(
                                  category,
                                  results
                                      .where(
                                        (entry) =>
                                            _category(entry.feature) ==
                                            category,
                                      )
                                      .toList(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _categoryPanel
  // 함수역할: 기능 범주 제목과 결과 행을 구분선으로 묶고 빈 범주는 숨긴다.
  // 매개변수: category (_FeatureCategory): 범주; entries (List<FeatureSearchEntry>): 범주 결과.
  // 반환값: 범주 패널 또는 SizedBox.shrink.
  Widget _categoryPanel(
    _FeatureCategory category,
    List<FeatureSearchEntry> entries,
  ) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MedBuddySearchPanel(
        key: ValueKey('feature-category-${category.name}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _heading(_english ? category.en : category.ko),
              ),
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _result(entries[index]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _category
  // 함수역할: 기능 목적지를 약 관리·기록·가족·의료·알림·표시·계정 범주로 분류한다.
  // 매개변수: feature (AppFeature): 목적지.
  // 반환값: 해당 _FeatureCategory.
  _FeatureCategory _category(AppFeature feature) => switch (feature) {
    AppFeature.medicationSearch ||
    AppFeature.manualMedication ||
    AppFeature.prescription ||
    AppFeature.pillIdentification ||
    AppFeature.medicationCabinet => _FeatureCategory.medications,
    AppFeature.schedule ||
    AppFeature.asNeeded ||
    AppFeature.medicationHistory ||
    AppFeature.historySharing ||
    AppFeature.homeSchedule => _FeatureCategory.records,
    AppFeature.caregiverLink ||
    AppFeature.caregiverSchedule ||
    AppFeature.chat => _FeatureCategory.family,
    AppFeature.nearbyPharmacy ||
    AppFeature.nearbyHospital ||
    AppFeature.healthRecommendation => _FeatureCategory.health,
    AppFeature.notificationInbox ||
    AppFeature.notifications ||
    AppFeature.notificationReception ||
    AppFeature.defaultTimes ||
    AppFeature.notificationPrivacy => _FeatureCategory.notifications,
    AppFeature.fontSize ||
    AppFeature.language ||
    AppFeature.timeFormat ||
    AppFeature.readingSpeed ||
    AppFeature.homeWidget => _FeatureCategory.display,
    AppFeature.account || AppFeature.dataUse => _FeatureCategory.account,
  };

  // 함수이름: _heading
  // 함수역할: 기능 결과 구역의 제목을 일정한 굵기·여백으로 표시한다.
  // 매개변수: title (String): 제목.
  // 반환값: 여백이 있는 Text 위젯.
  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: KeepWordsText(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: 0,
        color: MedBuddyColors.primaryDark,
      ),
    ),
  );

  // Function Name: _result
  // Description: Displays a feature name/menu path and serializes its asynchronous parent action so repeated taps cannot open duplicate destinations.
  // Parameters: entry (FeatureSearchEntry): feature result and labels.
  // Returns: Result row; the opening lock is released after the action finishes.
  Widget _result(FeatureSearchEntry entry) => Column(
    children: [
      ListTile(
        key: ValueKey('feature-${entry.feature.name}'),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        leading: Icon(_icon(entry.feature), color: MedBuddyColors.primaryDark),
        title: KeepWordsText(
          entry.title(_english),
          style: MedBuddyTextStyles.menuTitle,
        ),
        subtitle: KeepWordsText(
          entry.path(_english),
          style: MedBuddyTextStyles.menuBody,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          if (_openingFeature) return;
          FocusScope.of(context).unfocus();
          _openingFeature = true;
          try {
            await widget.onFeatureSelected(context, entry.feature);
          } finally {
            _openingFeature = false;
          }
        },
      ),
    ],
  );

  // 함수이름: _icon
  // 함수역할: 기능 목적지를 기존 화면과 일관된 Material 아이콘으로 구분한다.
  // 매개변수: feature (AppFeature): 목적지.
  // 반환값: 해당 기능의 IconData.
  IconData _icon(AppFeature feature) => switch (feature) {
    AppFeature.manualMedication => Icons.add_circle_outline,
    AppFeature.medicationSearch => Icons.search,
    AppFeature.prescription => Icons.document_scanner_outlined,
    AppFeature.pillIdentification => Icons.image_search_outlined,
    AppFeature.schedule ||
    AppFeature.asNeeded ||
    AppFeature.homeSchedule => Icons.calendar_month_outlined,
    AppFeature.medicationCabinet => Icons.inventory_2_outlined,
    AppFeature.medicationHistory => Icons.event_note_outlined,
    AppFeature.historySharing => Icons.share_outlined,
    AppFeature.caregiverLink => Icons.link,
    AppFeature.caregiverSchedule => Icons.supervisor_account_outlined,
    AppFeature.chat => Icons.chat_bubble_outline,
    AppFeature.nearbyPharmacy => Icons.storefront_outlined,
    AppFeature.nearbyHospital => Icons.local_hospital_outlined,
    AppFeature.healthRecommendation => Icons.monitor_heart_outlined,
    AppFeature.notificationInbox ||
    AppFeature.notifications ||
    AppFeature.notificationReception => Icons.notifications_none,
    AppFeature.defaultTimes || AppFeature.timeFormat => Icons.schedule,
    AppFeature.notificationPrivacy ||
    AppFeature.dataUse => Icons.privacy_tip_outlined,
    AppFeature.fontSize => Icons.text_fields,
    AppFeature.language => Icons.language,
    AppFeature.readingSpeed => Icons.record_voice_over_outlined,
    AppFeature.homeWidget => Icons.widgets_outlined,
    AppFeature.account => Icons.manage_accounts_outlined,
  };
}

// 클래스명: _FeatureCategory
// 역할: 기능 검색의 표시 범주와 양언어 제목.
// 주요 책임: 기능을 사용 목적별로 묶는 고정 범주를 제공한다.
// 속성: ko/en (String): 한국어·영어 범주명.
enum _FeatureCategory {
  medications('약 등록·관리', 'Add & manage medications'),
  records('복용 일정·기록', 'Schedules & records'),
  family('가족 연결·채팅', 'Family & chat'),
  health('병원·약국·건강', 'Healthcare & pharmacies'),
  notifications('알림·복용 시간', 'Notifications & dose times'),
  display('화면·음성·위젯', 'Display, voice & widgets'),
  account('계정·개인정보', 'Account & privacy');

  // 함수이름: _FeatureCategory
  // 함수역할: 범주별 두 언어 제목을 저장한다.
  // 매개변수: ko/en (String): 한국어·영어 제목.
  // 반환값: _FeatureCategory 열거값.
  const _FeatureCategory(this.ko, this.en);
  final String ko;
  final String en;
}
