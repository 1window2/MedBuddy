import 'package:flutter/material.dart';

import '../entities/prescription_change_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/expandable_medication_section.dart';

// 파일명: prescription_change_radar_ui_boundary.dart
// 역할: 이전 처방 대비 약품 추가·일정 변경·미확인 항목 비교를 제공한다.

// 클래스명: PrescriptionChangeRadarUI
// 역할: 처방 비교 상태와 추가·변경·미확인 약품을 담당한다.
// 주요 책임:
// - 관련 처방 존재 여부, 비교 기준일과 비교 생략 이유를 표시한다.
// - 추가, 이번 처방 미확인, 복약 일정 변경을 구분해 표시한다.
// 속성:
// - radar (PrescriptionChangeRadar): 이전 처방과의 비교 상태·변화 목록.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class PrescriptionChangeRadarUI extends StatelessWidget {
  final PrescriptionChangeRadar radar;
  final UserSetting userSetting;

  // 함수이름: PrescriptionChangeRadarUI
  // 함수역할: 처방 비교 상태와 추가·변경·미확인 약품에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - radar (PrescriptionChangeRadar): 이전 처방과의 비교 상태·변화 목록.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 PrescriptionChangeRadarUI 인스턴스.
  const PrescriptionChangeRadarUI({
    super.key,
    required this.radar,
    required this.userSetting,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 비교 상태와 추가·변경·미확인 약품 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 비교 상태와 추가·변경·미확인 약품에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _PrescriptionChangeText(userSetting.language);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.successBorder),
        boxShadow: MedBuddyShadows.card,
      ),
      child: ExpandableMedicationSection(
        initiallyExpanded: false,
        isEnglish: text.isEnglish,
        toggleKey: const Key('prescription-radar-toggle'),
        expandLabel: text.isEnglish ? 'Show prescription changes' : '처방 변화 펼치기',
        collapseLabel: text.isEnglish
            ? 'Hide prescription changes'
            : '처방 변화 접기',
        headerBuilder: (toggle) => _RadarHeader(
          text: text,
          comparisonWindowDays: radar.comparisonWindowDays,
          toggle: toggle,
        ),
        details: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child:
              radar.hasPreviousPrescription &&
                  radar.comparisonStatus ==
                      PrescriptionComparisonStatus.comparable
              ? _buildComparisonContent(text)
              : _buildUnavailableContent(text),
        ),
      ),
    );
  }

  // 함수이름: _buildUnavailableContent
  // 함수역할: 비교 실패·만료·무관한 처방 상태에 맞춘 아이콘과 생략 이유를 표시한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 처방 비교 상태와 추가·변경·미확인 약품에 쓰는 위젯 트리.
  Widget _buildUnavailableContent(_PrescriptionChangeText text) {
    final icon = switch (radar.comparisonStatus) {
      PrescriptionComparisonStatus.expired => Icons.event_busy_outlined,
      PrescriptionComparisonStatus.unrelated => Icons.compare_arrows,
      _ => Icons.history_toggle_off,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MedBuddyColors.textMuted, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.unavailableMessage(
              radar.comparisonStatus,
              radar.comparisonWindowDays,
            ),
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }

  // 함수이름: _buildComparisonContent
  // 함수역할: 비교 기준일·변화 수·약별 차이 또는 변화 없음을 표시한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 처방 비교 상태와 추가·변경·미확인 약품에 쓰는 위젯 트리.
  Widget _buildComparisonContent(_PrescriptionChangeText text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.comparisonPeriod(
            radar.previousPrescriptionDate,
            radar.currentPrescriptionDate,
          ),
          style: TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (radar.changes.isNotEmpty) ...[
          _ChangeSummary(radar: radar, text: text),
          // 함수이름: _buildComparisonContent.map callback
          // 함수역할: 처방 비교 상태와 추가·변경·미확인 약품의 변환값을 `_MedicationChangeRow(change: change, text: text)` 규칙으로 계산한다.
          // 매개변수:
          // - change (콜백 계약에서 추론): 약품 한 건의 추가·일정 변경·미확인 정보.
          // 반환값: 컬렉션 연산에 전달할 변환값.
        ] else if (radar.hasChanges)
          Text(
            text.isEnglish
                ? 'Change details are unavailable.'
                : '변경 상세 정보를 불러오지 못했습니다.',
          )
        else
          _NoChangeMessage(text: text),
      ],
    );
  }
}

// 클래스명: PrescriptionChangeRadarLoadingUI
// 역할: 분석 결과를 가리지 않는 처방 비교 진행 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 분석 결과를 가리지 않는 처방 비교 진행 표시 위젯을 구성한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class PrescriptionChangeRadarLoadingUI extends StatelessWidget {
  final UserSetting userSetting;

  // 함수이름: PrescriptionChangeRadarLoadingUI
  // 함수역할: 분석 결과를 가리지 않는 처방 비교 진행 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 PrescriptionChangeRadarLoadingUI 인스턴스.
  const PrescriptionChangeRadarLoadingUI({
    super.key,
    required this.userSetting,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 분석 결과를 가리지 않는 처방 비교 진행 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 분석 결과를 가리지 않는 처방 비교 진행 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _PrescriptionChangeText(userSetting.language);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.successBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: MedBuddyColors.primary,
              strokeWidth: 2.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.loading,
              style: TextStyle(
                color: MedBuddyColors.primaryDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _RadarHeader
// 역할: 처방 변화 제목과 비교 기간 설명을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방 변화 제목과 비교 기간 설명 위젯을 구성한다.
// 속성:
// - comparisonWindowDays (int): 이전 처방을 찾는 비교 기간의 일수.
class _RadarHeader extends StatelessWidget {
  final _PrescriptionChangeText text;
  final int comparisonWindowDays;
  final Widget toggle;

  // 함수이름: _RadarHeader
  // 함수역할: 처방 변화 제목과 비교 기간 설명에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - comparisonWindowDays (int): 이전 처방을 찾는 비교 기간의 일수.
  // 반환값: 입력 설정이 반영된 _RadarHeader 인스턴스.
  const _RadarHeader({
    required this.text,
    required this.comparisonWindowDays,
    required this.toggle,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 변화 제목과 비교 기간 설명 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 변화 제목과 비교 기간 설명에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 4, 14),
      decoration: const BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: MedBuddyColors.successBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radar, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.title,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  text.subtitle(comparisonWindowDays),
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 12.5,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

// 클래스명: _ChangeSummary
// 역할: 추가·일정 변경·미확인 약 개수를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 추가·일정 변경·미확인 약 개수 위젯을 구성한다.
// 속성:
// - summary (PrescriptionChangeSummary): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
class _ChangeSummary extends StatefulWidget {
  final PrescriptionChangeRadar radar;
  final _PrescriptionChangeText text;

  // 함수이름: _ChangeSummary
  // 함수역할: 추가·일정 변경·미확인 약 개수에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - summary (PrescriptionChangeSummary): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _ChangeSummary 인스턴스.
  const _ChangeSummary({required this.radar, required this.text});

  @override
  State<_ChangeSummary> createState() => _ChangeSummaryState();
}

class _ChangeSummaryState extends State<_ChangeSummary> {
  static const _pageSize = 3;
  static const _types = [
    PrescriptionChangeType.scheduleChanged,
    PrescriptionChangeType.added,
    PrescriptionChangeType.missing,
    PrescriptionChangeType.unknown,
  ];
  late PrescriptionChangeType _selected = _types.firstWhere(
    (type) => widget.radar.changes.any((change) => change.type == type),
    orElse: () => PrescriptionChangeType.scheduleChanged,
  );
  int _page = 0;
  int? _expandedIndex;

  @override
  void didUpdateWidget(covariant _ChangeSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.radar.changes, widget.radar.changes)) {
      _page = 0;
      _expandedIndex = null;
    }
  }

  void _select(PrescriptionChangeType type) => setState(() {
    _selected = type;
    _page = 0;
    _expandedIndex = null;
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 추가·일정 변경·미확인 약 개수 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 추가·일정 변경·미확인 약 개수에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final changes = widget.radar.changes.indexed
        .where((entry) => entry.$2.type == _selected)
        .toList(growable: false);
    final lastPage = changes.isEmpty ? 0 : (changes.length - 1) ~/ _pageSize;
    final page = _page.clamp(0, lastPage);
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, changes.length);
    final types = _types
        .where(
          (type) =>
              type != PrescriptionChangeType.unknown ||
              widget.radar.changes.any((change) => change.type == type),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = types.length > 3 ? 2 : 3;
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final type in types)
                  SizedBox(
                    width: (constraints.maxWidth - (columns - 1) * 4) / columns,
                    child: _SummaryChip(
                      key: Key('radar-tab-${type.name}'),
                      label: text.category(type),
                      count: widget.radar.changes
                          .where((change) => change.type == type)
                          .length,
                      selected: _selected == type,
                      onTap: () => _select(type),
                      foreground: _changeTypeColors(type).foreground,
                      background: _changeTypeColors(type).background,
                    ),
                  ),
              ],
            );
          },
        ),
        if (_selected == PrescriptionChangeType.missing && changes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              text.missing,
              style: const TextStyle(
                fontSize: 12.5,
                color: MedBuddyColors.textMuted,
              ),
            ),
          ),
        if (changes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              text.isEnglish
                  ? 'No medications in this category.'
                  : '이 분류에 해당하는 약이 없습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
        for (final (index, change) in changes.skip(start).take(_pageSize))
          _MedicationChangeRow(
            key: Key('radar-change-$index'),
            change: change,
            text: text,
            isExpanded: _expandedIndex == index,
            onToggle: () => setState(
              () => _expandedIndex = _expandedIndex == index ? null : index,
            ),
          ),
        if (changes.length > _pageSize)
          Row(
            children: [
              IconButton(
                key: const Key('radar-previous-page'),
                tooltip: text.isEnglish ? 'Previous medications' : '이전 약 목록',
                onPressed: page == 0
                    ? null
                    : () => setState(() {
                        _page = page - 1;
                        _expandedIndex = null;
                      }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${start + 1}–$end / ${changes.length}${text.isEnglish ? '' : '개'}',
                    key: const Key('radar-page-range'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MedBuddyColors.textMuted,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('radar-next-page'),
                tooltip: text.isEnglish ? 'Next medications' : '다음 약 목록',
                onPressed: end == changes.length
                    ? null
                    : () => setState(() {
                        _page = page + 1;
                        _expandedIndex = null;
                      }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

// 클래스명: _SummaryChip
// 역할: 처방 변화 유형별 색상 개수 표식을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방 변화 유형별 색상 개수 표식 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - foreground (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - background (Color): 항목의 바탕 색상.
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  // 함수이름: _SummaryChip
  // 함수역할: 처방 변화 유형별 색상 개수 표식에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - foreground (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - background (Color): 항목의 바탕 색상.
  // 반환값: 입력 설정이 반영된 _SummaryChip 인스턴스.
  const _SummaryChip({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 변화 유형별 색상 개수 표식 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 변화 유형별 색상 개수 표식에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? background : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? foreground : MedBuddyColors.divider,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? foreground : MedBuddyColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? foreground : MedBuddyColors.textMuted,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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

// 클래스명: _MedicationChangeRow
// 역할: 약품 변화 유형과 변경 전후 일정 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품 변화 유형과 변경 전후 일정 값 위젯을 구성한다.
// 속성:
// - change (PrescriptionMedicationChange): 약품 한 건의 추가·일정 변경·미확인 정보.
class _MedicationChangeRow extends StatelessWidget {
  final PrescriptionMedicationChange change;
  final _PrescriptionChangeText text;
  final bool isExpanded;
  final VoidCallback onToggle;

  // 함수이름: _MedicationChangeRow
  // 함수역할: 약품 변화 유형과 변경 전후 일정 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - change (PrescriptionMedicationChange): 약품 한 건의 추가·일정 변경·미확인 정보.
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _MedicationChangeRow 인스턴스.
  const _MedicationChangeRow({
    super.key,
    required this.change,
    required this.text,
    required this.isExpanded,
    required this.onToggle,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 변화 유형과 변경 전후 일정 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 변화 유형과 변경 전후 일정 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final canExpand =
        change.changedFields.isNotEmpty &&
        (change.previous != null || change.current != null);
    final content = Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.itemName.isEmpty
                      ? text.unknownMedication
                      : change.itemName,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                if (change.changedFields.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    change.changedFields.map(text.fieldLabel).join(' · '),
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (canExpand)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: MedBuddyColors.primaryDark,
            ),
          ),
      ],
    );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canExpand)
            Semantics(
              button: true,
              expanded: isExpanded,
              child: InkWell(onTap: onToggle, child: content),
            )
          else
            content,
          if (canExpand && isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Table(
                key: const Key('radar-change-detail'),
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: MedBuddyColors.surfaceSubtle,
                    ),
                    children: [
                      for (final title in [
                        text.isEnglish ? 'Field' : '항목',
                        text.isEnglish ? 'Previous' : '이전',
                        text.isEnglish ? 'Current' : '이번',
                      ])
                        _detailCell(title, heading: true),
                    ],
                  ),
                  ...change.changedFields.map(
                    // 함수이름: build.map callback
                    // 함수역할: 변경된 일정 항목의 이름과 이전·이번 값을 비교 표의 한 행으로 만든다.
                    // 매개변수:
                    // - field (콜백 계약에서 추론): 편집 창에서 선택할 복약 정보 입력 항목.
                    // 반환값: 컬렉션 연산에 전달할 변환값.
                    (field) => TableRow(
                      children: [
                        _detailCell(text.fieldLabel(field)),
                        _detailCell(
                          text.snapshotValue(
                            change.previous?.valueForField(field),
                          ),
                        ),
                        _detailCell(
                          text.snapshotValue(
                            change.current?.valueForField(field),
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

  Widget _detailCell(String value, {bool heading = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(
      value,
      style: TextStyle(
        color: heading ? MedBuddyColors.textMuted : MedBuddyColors.textStrong,
        fontSize: 13,
        fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );
}

// 클래스명: _NoChangeMessage
// 역할: 비교 가능한 처방에 변화가 없다는 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 비교 가능한 처방에 변화가 없다는 안내 위젯을 구성한다.
// 속성:
// - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
class _NoChangeMessage extends StatelessWidget {
  final _PrescriptionChangeText text;

  // 함수이름: _NoChangeMessage
  // 함수역할: 비교 가능한 처방에 변화가 없다는 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _NoChangeMessage 인스턴스.
  const _NoChangeMessage({required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 비교 가능한 처방에 변화가 없다는 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 비교 가능한 처방에 변화가 없다는 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: MedBuddyColors.primary,
          size: 24,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text.noChanges,
            style: TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// 함수이름: _changeTypeColors
// 함수역할: 처방 변화 유형별 분류 칩의 글자·배경 색상을 고른다.
// 매개변수:
// - type (PrescriptionChangeType): 색상을 고를 처방 변화 유형.
// 반환값: 칩 글자색(foreground)과 배경색(background).
({Color foreground, Color background}) _changeTypeColors(
  PrescriptionChangeType type,
) => switch (type) {
  PrescriptionChangeType.added => (
    foreground: MedBuddyColors.primaryDark,
    background: MedBuddyColors.successSurface,
  ),
  PrescriptionChangeType.missing => (
    foreground: MedBuddyColors.danger,
    background: MedBuddyColors.surfaceSubtle,
  ),
  PrescriptionChangeType.scheduleChanged => (
    foreground: MedBuddyColors.reminderAccent,
    background: MedBuddyColors.warningSurface,
  ),
  PrescriptionChangeType.unknown => (
    foreground: MedBuddyColors.textMuted,
    background: MedBuddyColors.lavenderSurface,
  ),
};

// 클래스명: _PrescriptionChangeText
// 역할: 이전 처방 대비 약품 추가·일정 변경·미확인 항목 비교에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 이전 처방 대비 약품 추가·일정 변경·미확인 항목 비교에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _PrescriptionChangeText {
  final String language;

  // 함수이름: _PrescriptionChangeText
  // 함수역할: 이전 처방 대비 약품 추가·일정 변경·미확인 항목 비교에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _PrescriptionChangeText 인스턴스.
  const _PrescriptionChangeText(this.language);

  String category(PrescriptionChangeType type) => switch (type) {
    PrescriptionChangeType.scheduleChanged => isEnglish ? 'Changed' : '일정 변경',
    PrescriptionChangeType.added => isEnglish ? 'New' : '새로 확인',
    PrescriptionChangeType.missing => isEnglish ? 'Not found' : '이번에 없음',
    PrescriptionChangeType.unknown => isEnglish ? 'Other' : '기타',
  };

  String fieldLabel(String field) => switch (field) {
    'dosage_per_time' => isEnglish ? 'Dose' : '1회 투약량',
    'daily_frequency' => isEnglish ? 'Frequency' : '1일 횟수',
    'total_days' => isEnglish ? 'Duration' : '총 투약일',
    _ => isEnglish ? 'Schedule' : '복약 일정',
  };

  String snapshotValue(String? value) => value == null || value.trim().isEmpty
      ? (isEnglish ? 'Not recorded' : '기록 없음')
      : value.trim();

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방 변화 레이더" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Prescription Change Radar' : '처방 변화 레이더';
  // 함수이름: subtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "최근 $windowDays일의 관련 처방과 비교해요" 문구를 제공한다.
  // 매개변수:
  // - windowDays (int): 이전 처방을 찾는 비교 기간의 일수.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String subtitle(int windowDays) => isEnglish
      ? 'Compared with a related prescription from the last $windowDays days'
      : '최근 $windowDays일의 관련 처방과 비교해요';
  // 함수이름: noPreviousPrescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "아직 비교할 이전 처방이 없습니다. 이번 처방을 저장하면 다음 처방부터 변화를 확인할 수 있어요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noPreviousPrescription => isEnglish
      ? 'There is no previous prescription to compare yet. Save this prescription to use it as a baseline next time.'
      : '아직 비교할 이전 처방이 없습니다. 이번 처방을 저장하면 다음 처방부터 변화를 확인할 수 있어요.';
  // 함수이름: loading
  // 함수역할: 현재 언어와 입력값에 맞춰 "이전 처방과 달라진 점을 확인하고 있어요..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loading => isEnglish
      ? 'Comparing with your previous prescription...'
      : '이전 처방과 달라진 점을 확인하고 있어요...';
  // 함수이름: noChanges
  // 함수역할: 현재 언어와 입력값에 맞춰 "약품 구성과 복약 일정에서 달라진 점을 찾지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noChanges => isEnglish
      ? 'No medication or schedule changes were found.'
      : '약품 구성과 복약 일정에서 달라진 점을 찾지 못했습니다.';
  // 함수이름: missing
  // 함수역할: 현재 언어와 입력값에 맞춰 "이번 처방에서 확인되지 않음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get missing =>
      isEnglish ? 'Not found in this prescription' : '이번 처방에서 확인되지 않음';
  // 함수이름: unknownMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "약품명 확인 필요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get unknownMedication =>
      isEnglish ? 'Medication name unavailable' : '약품명 확인 필요';
  // 함수이름: unavailableMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "이전 처방 기록은 있지만 최근 $windowDays일 비교 기간 안의 처방은 없습니다." 문구를 제공한다.
  // 매개변수:
  // - status (PrescriptionComparisonStatus): 현재 연결·분석·비교 진행 상태.
  // - windowDays (int): 이전 처방을 찾는 비교 기간의 일수.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String unavailableMessage(
    PrescriptionComparisonStatus status,
    int windowDays,
  ) {
    return switch (status) {
      PrescriptionComparisonStatus.expired =>
        isEnglish
            ? 'Previous prescriptions exist, but none are within the $windowDays-day comparison window.'
            : '이전 처방 기록은 있지만 최근 $windowDays일 비교 기간 안의 처방은 없습니다.',
      PrescriptionComparisonStatus.unrelated =>
        isEnglish
            ? 'No sufficiently related prescription was found in the last $windowDays days, so comparison was skipped.'
            : '최근 $windowDays일 기록에서 관련성이 충분한 처방을 찾지 못해 비교를 생략했어요.',
      _ => noPreviousPrescription,
    };
  }

  // 함수이름: comparisonPeriod
  // 함수역할: 현재 언어와 입력값에 맞춰 "비교 기준: $previousText → $currentText" 문구를 제공한다.
  // 매개변수:
  // - previous (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // - current (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String comparisonPeriod(DateTime? previous, DateTime? current) {
    final previousText = _formatDate(previous);
    final currentText = _formatDate(current);
    return isEnglish
        ? 'Comparison: $previousText → $currentText'
        : '비교 기준: $previousText → $currentText';
  }

  // 함수이름: _formatDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "날짜 미상" 문구를 제공한다.
  // 매개변수:
  // - value (DateTime?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _formatDate(DateTime? value) {
    if (value == null) {
      return isEnglish ? 'Unknown' : '날짜 미상';
    }
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }
}
