// 파일명: feature_search_ui_boundary.dart
// 역할: 주요 기능과 자연스러운 검색 표현의 결과를 보여주고 선택한 목적지만 반환한다.
import 'package:flutter/material.dart';
import '../controls/find_app_feature_control.dart';
import '../entities/feature_search_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';

// 클래스명: FeatureSearchUI
// 역할: 계정 데이터 조회 없이 기능 검색·초기화·결과 선택을 제공한다.
class FeatureSearchUI extends StatefulWidget {
  final bool isEnglish;
  final bool widgetSupported;

  // 함수이름: FeatureSearchUI
  // 함수역할: 표시 언어와 기기 기능 지원 범위를 받아 검색 화면을 만든다.
  const FeatureSearchUI({
    super.key,
    this.isEnglish = false,
    this.widgetSupported = true,
  });

  @override
  State<FeatureSearchUI> createState() => _FeatureSearchUIState();
}

// 클래스명: _FeatureSearchUIState
// 역할: 현재 화면에만 검색어를 보관하며 종료할 때 폐기한다.
class _FeatureSearchUIState extends State<FeatureSearchUI> {
  final _query = TextEditingController();
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
        : [
            for (final id in FindAppFeature.common)
              ...available.where((entry) => entry.feature == id),
          ];
    final others = available.where(
      (entry) => !FindAppFeature.common.contains(entry.feature),
    );
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
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: TextField(
                          key: const Key('featureSearchInput'),
                          controller: _query,
                          maxLength: 120,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            labelText: _english ? 'Feature search' : '기능 검색',
                            hintText: _english
                                ? 'Bigger text, send records'
                                : '글씨 크게, 먹은 기록 보내기',
                            counterText: '',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: hasQuery
                                ? IconButton(
                                    key: const Key('featureSearchClear'),
                                    tooltip: _english
                                        ? 'Clear search'
                                        : '검색어 지우기',
                                    onPressed: () => setState(_query.clear),
                                    icon: const Icon(Icons.close),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            _heading(
                              hasQuery
                                  ? (_english ? 'Results' : '검색 결과')
                                  : (_english ? 'Quick access' : '주요 기능'),
                            ),
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
                            for (final entry in results) _result(entry),
                            if (!hasQuery) ...[
                              const SizedBox(height: 24),
                              _heading(_english ? 'All features' : '전체 기능'),
                              for (final entry in others) _result(entry),
                            ],
                          ],
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

  // 함수이름: _heading
  // 함수역할: 결과 구역의 제목을 기존 설정 화면과 같은 크기로 표시한다.
  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
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
        title: Text(
          entry.title(_english),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(entry.path(_english)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          FocusScope.of(context).unfocus();
          Navigator.pop(context, entry.feature);
        },
      ),
      const Divider(height: 1),
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
