// 파일명: feature_search_ui_boundary.dart
// 역할: 주요 기능과 자연스러운 검색 표현의 결과를 보여주고 선택한 목적지만 반환한다.
import 'package:flutter/material.dart';
import '../controls/find_app_feature_control.dart';
import '../entities/feature_search_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/medbuddy_search_field.dart';

// 클래스명: FeatureSearchUI
// 역할: 계정 데이터 조회 없이 기능 검색·초기화·결과 선택을 제공한다.
class FeatureSearchUI extends StatefulWidget {
  final bool isEnglish;
  final bool widgetSupported;
  final Future<void> Function(BuildContext, AppFeature) onFeatureSelected;

  // 함수이름: FeatureSearchUI
  // 함수역할: 표시 언어와 기기 기능 지원 범위를 받아 검색 화면을 만든다.
  const FeatureSearchUI({
    super.key,
    this.isEnglish = false,
    this.widgetSupported = true,
    required this.onFeatureSelected,
  });

  @override
  State<FeatureSearchUI> createState() => _FeatureSearchUIState();
}

// 클래스명: _FeatureSearchUIState
// 역할: 현재 화면에만 검색어를 보관하며 종료할 때 폐기한다.
class _FeatureSearchUIState extends State<FeatureSearchUI> {
  final _query = TextEditingController();
  bool _openingFeature = false;
  bool get _english => widget.isEnglish;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

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
                                  child: Text(
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

  _FeatureCategory _category(AppFeature feature) => switch (feature) {
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
  // 함수역할: 결과 구역의 제목을 기존 설정 화면과 같은 크기로 표시한다.
  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
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

  // 함수이름: _result
  // 함수역할: 아이콘·기능명·기존 메뉴 위치를 표시하고 선택한 항목만 반환한다.
  Widget _result(FeatureSearchEntry entry) => Column(
    children: [
      ListTile(
        key: ValueKey('feature-${entry.feature.name}'),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        leading: Icon(_icon(entry.feature), color: MedBuddyColors.primaryDark),
        title: Text(entry.title(_english), style: MedBuddyTextStyles.menuTitle),
        subtitle: Text(
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
  // 함수역할: 기존 화면과 일관된 Material 아이콘으로 목적지를 구분한다.
  IconData _icon(AppFeature feature) => switch (feature) {
    AppFeature.manualMedication => Icons.add_circle_outline,
    AppFeature.prescription => Icons.document_scanner_outlined,
    AppFeature.pillIdentification => Icons.image_search_outlined,
    AppFeature.schedule ||
    AppFeature.asNeeded ||
    AppFeature.homeSchedule => Icons.calendar_month_outlined,
    AppFeature.medicationCabinet => Icons.medication_outlined,
    AppFeature.medicationHistory => Icons.event_note_outlined,
    AppFeature.historySharing => Icons.share_outlined,
    AppFeature.caregiverLink => Icons.link,
    AppFeature.caregiverSchedule => Icons.supervisor_account_outlined,
    AppFeature.chat => Icons.chat_bubble_outline,
    AppFeature.nearbyPharmacy => Icons.local_pharmacy_outlined,
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

enum _FeatureCategory {
  medications('약 등록·관리', 'Add & manage medications'),
  records('복용 일정·기록', 'Schedules & records'),
  family('가족 연결·채팅', 'Family & chat'),
  health('병원·약국·건강', 'Healthcare & pharmacies'),
  notifications('알림·복용 시간', 'Notifications & dose times'),
  display('화면·음성·위젯', 'Display, voice & widgets'),
  account('계정·개인정보', 'Account & privacy');

  const _FeatureCategory(this.ko, this.en);
  final String ko;
  final String en;
}
