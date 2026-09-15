import 'package:flutter/material.dart';

import '../entities/prescription_change_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_change_radar_ui_boundary.dart
// 역할: 이전 처방 대비 약품 추가·일정 변경·미확인 항목 비교를 제공한다.

// 클래스명: PrescriptionChangeRadarUI
// 역할: 처방 비교 상태와 추가·변경·미확인 약품을 담당한다.
// 주요 책임:
// - 관련 처방 존재 여부, 비교 기준일과 비교 생략 이유를 표시한다.
// - 추가, 이번 처방 미확인, 복약 일정 변경을 구분해 표시한다.
// - 변화 정보가 복용 중단 지시가 아님을 사용자에게 안내한다.
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
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: const Color(0xFFB7E4D3), width: 2),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RadarHeader(
            text: text,
            scale: scale,
            comparisonWindowDays: radar.comparisonWindowDays,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child:
                radar.hasPreviousPrescription &&
                    radar.comparisonStatus ==
                        PrescriptionComparisonStatus.comparable
                ? _buildComparisonContent(text, scale)
                : _buildUnavailableContent(text, scale),
          ),
        ],
      ),
    );
  }

  // 함수이름: _buildUnavailableContent
  // 함수역할: 비교 실패·만료·무관한 처방 상태에 맞춘 아이콘과 생략 이유를 표시한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 처방 비교 상태와 추가·변경·미확인 약품에 쓰는 위젯 트리.
  Widget _buildUnavailableContent(_PrescriptionChangeText text, double scale) {
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
              fontSize: 14 * scale,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }

  // 함수이름: _buildComparisonContent
  // 함수역할: 비교 기준일·변화 수·약별 차이 또는 변화 없음과 안전 안내를 표시한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 처방 비교 상태와 추가·변경·미확인 약품에 쓰는 위젯 트리.
  Widget _buildComparisonContent(_PrescriptionChangeText text, double scale) {
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
            fontSize: 13 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (radar.hasChanges) ...[
          _ChangeSummary(summary: radar.summary, text: text, scale: scale),
          const SizedBox(height: 14),
          ...radar.changes.map(
            // 함수이름: _buildComparisonContent.map callback
            // 함수역할: 처방 비교 상태와 추가·변경·미확인 약품의 변환값을 `_MedicationChangeRow(change: change, text: text, scale: scale)` 규칙으로 계산한다.
            // 매개변수:
            // - change (콜백 계약에서 추론): 약품 한 건의 추가·일정 변경·미확인 정보.
            // 반환값: 컬렉션 연산에 전달할 변환값.
            (change) =>
                _MedicationChangeRow(change: change, text: text, scale: scale),
          ),
        ] else
          _NoChangeMessage(text: text, scale: scale),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: MedBuddyRadii.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFFB7791F),
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text.safetyNotice,
                  style: TextStyle(
                    color: const Color(0xFF7C5A13),
                    fontSize: 12.5 * scale,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final scale = userSetting.contentTextScale;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF4),
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: const Color(0xFFB7E4D3), width: 2),
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
                fontSize: 14 * scale,
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
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - comparisonWindowDays (int): 이전 처방을 찾는 비교 기간의 일수.
class _RadarHeader extends StatelessWidget {
  final _PrescriptionChangeText text;
  final double scale;
  final int comparisonWindowDays;

  // 함수이름: _RadarHeader
  // 함수역할: 처방 변화 제목과 비교 기간 설명에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - comparisonWindowDays (int): 이전 처방을 찾는 비교 기간의 일수.
  // 반환값: 입력 설정이 반영된 _RadarHeader 인스턴스.
  const _RadarHeader({
    required this.text,
    required this.scale,
    required this.comparisonWindowDays,
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
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFEAFBF4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(color: Color(0xFFB7E4D3), width: 1.5),
        ),
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
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  text.subtitle(comparisonWindowDays),
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 12.5 * scale,
                    letterSpacing: 0,
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

// 클래스명: _ChangeSummary
// 역할: 추가·일정 변경·미확인 약 개수를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 추가·일정 변경·미확인 약 개수 위젯을 구성한다.
// 속성:
// - summary (PrescriptionChangeSummary): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _ChangeSummary extends StatelessWidget {
  final PrescriptionChangeSummary summary;
  final _PrescriptionChangeText text;
  final double scale;

  // 함수이름: _ChangeSummary
  // 함수역할: 추가·일정 변경·미확인 약 개수에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - summary (PrescriptionChangeSummary): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _ChangeSummary 인스턴스.
  const _ChangeSummary({
    required this.summary,
    required this.text,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 추가·일정 변경·미확인 약 개수 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 추가·일정 변경·미확인 약 개수에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (summary.addedCount > 0)
          _SummaryChip(
            label: text.addedCount(summary.addedCount),
            foreground: const Color(0xFF047857),
            background: const Color(0xFFDFF7EC),
            scale: scale,
          ),
        if (summary.scheduleChangedCount > 0)
          _SummaryChip(
            label: text.changedCount(summary.scheduleChangedCount),
            foreground: const Color(0xFF9A6700),
            background: const Color(0xFFFFF2C7),
            scale: scale,
          ),
        if (summary.missingCount > 0)
          _SummaryChip(
            label: text.missingCount(summary.missingCount),
            foreground: const Color(0xFFB42318),
            background: const Color(0xFFFFE4E2),
            scale: scale,
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
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final double scale;

  // 함수이름: _SummaryChip
  // 함수역할: 처방 변화 유형별 색상 개수 표식에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - foreground (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - background (Color): 항목의 바탕 색상.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _SummaryChip 인스턴스.
  const _SummaryChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 변화 유형별 색상 개수 표식 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 변화 유형별 색상 개수 표식에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: MedBuddyRadii.pill,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12.5 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
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
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _MedicationChangeRow extends StatelessWidget {
  final PrescriptionMedicationChange change;
  final _PrescriptionChangeText text;
  final double scale;

  // 함수이름: _MedicationChangeRow
  // 함수역할: 약품 변화 유형과 변경 전후 일정 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - change (PrescriptionMedicationChange): 약품 한 건의 추가·일정 변경·미확인 정보.
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _MedicationChangeRow 인스턴스.
  const _MedicationChangeRow({
    required this.change,
    required this.text,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 변화 유형과 변경 전후 일정 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 변화 유형과 변경 전후 일정 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final presentation = _ChangePresentation.fromType(change.type, text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(presentation.icon, color: presentation.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.itemName.isEmpty
                      ? text.unknownMedication
                      : change.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  presentation.label,
                  style: TextStyle(
                    color: presentation.color,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                if (change.type == PrescriptionChangeType.scheduleChanged)
                  ...change.changedFields.map(
                    // 함수이름: build.map callback
                    // 함수역할: 약품 변화 유형과 변경 전후 일정 값의 변환값을 `Padding(padding: const EdgeInsets.only(top: 4), child: Text(text.changedValue(field, change.previous?.valueForField(field)...` 규칙으로 계산한다.
                    // 매개변수:
                    // - field (콜백 계약에서 추론): 편집 창에서 선택할 복약 정보 입력 항목.
                    // 반환값: 컬렉션 연산에 전달할 변환값.
                    (field) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        text.changedValue(
                          field,
                          change.previous?.valueForField(field) ?? '',
                          change.current?.valueForField(field) ?? '',
                        ),
                        style: TextStyle(
                          color: MedBuddyColors.textMuted,
                          fontSize: 12.5 * scale,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
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

// 클래스명: _NoChangeMessage
// 역할: 비교 가능한 처방에 변화가 없다는 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 비교 가능한 처방에 변화가 없다는 안내 위젯을 구성한다.
// 속성:
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _NoChangeMessage extends StatelessWidget {
  final _PrescriptionChangeText text;
  final double scale;

  // 함수이름: _NoChangeMessage
  // 함수역할: 비교 가능한 처방에 변화가 없다는 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _NoChangeMessage 인스턴스.
  const _NoChangeMessage({required this.text, required this.scale});

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
              fontSize: 14 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _ChangePresentation
// 역할: 처방 변화 유형별 아이콘·색상·문구를 담당한다.
// 주요 책임:
// - 처방 변화 유형별 아이콘·색상·문구 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
class _ChangePresentation {
  final IconData icon;
  final Color color;
  final String label;

  // 함수이름: _ChangePresentation
  // 함수역할: 처방 변화 유형별 아이콘·색상·문구 관련 값을 _ChangePresentation 인스턴스에 담는다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // 반환값: 입력 설정이 반영된 _ChangePresentation 인스턴스.
  const _ChangePresentation({
    required this.icon,
    required this.color,
    required this.label,
  });

  // 함수이름: _ChangePresentation.fromType
  // 함수역할: 추가·일정 변경·이번 처방 미확인 유형을 아이콘·색상·현지화 라벨로 변환한다.
  // 매개변수:
  // - type (PrescriptionChangeType): 시·분 또는 처방 변화 등 현재 분기 종류.
  // - text (_PrescriptionChangeText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _ChangePresentation 인스턴스.
  factory _ChangePresentation.fromType(
    PrescriptionChangeType type,
    _PrescriptionChangeText text,
  ) {
    return switch (type) {
      PrescriptionChangeType.added => _ChangePresentation(
        icon: Icons.add_circle_outline,
        color: const Color(0xFF047857),
        label: text.added,
      ),
      PrescriptionChangeType.missing => _ChangePresentation(
        icon: Icons.remove_circle_outline,
        color: const Color(0xFFB42318),
        label: text.missing,
      ),
      PrescriptionChangeType.scheduleChanged => _ChangePresentation(
        icon: Icons.tune,
        color: const Color(0xFF9A6700),
        label: text.scheduleChanged,
      ),
      PrescriptionChangeType.unknown => _ChangePresentation(
        icon: Icons.help_outline,
        color: MedBuddyColors.textMuted,
        label: text.unknownChange,
      ),
    };
  }
}

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

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

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
  // 함수이름: added
  // 함수역할: 현재 언어와 입력값에 맞춰 "새롭게 확인됨" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get added => isEnglish ? 'Newly found' : '새롭게 확인됨';
  // 함수이름: missing
  // 함수역할: 현재 언어와 입력값에 맞춰 "이번 처방에서 확인되지 않음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get missing =>
      isEnglish ? 'Not found in this prescription' : '이번 처방에서 확인되지 않음';
  // 함수이름: scheduleChanged
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 일정 변경" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleChanged => isEnglish ? 'Schedule changed' : '복약 일정 변경';
  // 함수이름: unknownChange
  // 함수역할: 현재 언어와 입력값에 맞춰 "변화 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get unknownChange => isEnglish ? 'Change found' : '변화 확인';
  // 함수이름: unknownMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "약품명 확인 필요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get unknownMedication =>
      isEnglish ? 'Medication name unavailable' : '약품명 확인 필요';
  // 함수이름: safetyNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 비교는 복용 시작·중단 지시가 아닙니다. 실제 변경 여부는 처방전이나 의료진을 통해 확인해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get safetyNotice => isEnglish
      ? 'This comparison is not an instruction to start or stop medication. Confirm changes with the prescription or a healthcare professional.'
      : '이 비교는 복용 시작·중단 지시가 아닙니다. 실제 변경 여부는 처방전이나 의료진을 통해 확인해주세요.';

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

  // 함수이름: addedCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "추가 $count" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String addedCount(int count) => isEnglish ? 'Added $count' : '추가 $count';
  // 함수이름: changedCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "일정 변경 $count" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String changedCount(int count) =>
      isEnglish ? 'Changed $count' : '일정 변경 $count';
  // 함수이름: missingCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "미확인 $count" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String missingCount(int count) =>
      isEnglish ? 'Not found $count' : '미확인 $count';

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

  // 함수이름: changedValue
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 투약량" 문구를 제공한다.
  // 매개변수:
  // - field (String): 편집 창에서 선택할 복약 정보 입력 항목.
  // - previous (String): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // - current (String): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String changedValue(String field, String previous, String current) {
    final label = switch (field) {
      'dosage_per_time' => isEnglish ? 'Dose' : '1회 투약량',
      'daily_frequency' => isEnglish ? 'Frequency' : '1일 횟수',
      'total_days' => isEnglish ? 'Duration' : '총 투약일',
      _ => isEnglish ? 'Schedule' : '복약 일정',
    };
    final emptyValue = isEnglish ? 'No information' : '정보 없음';
    final previousText = previous.trim().isEmpty ? emptyValue : previous.trim();
    final currentText = current.trim().isEmpty ? emptyValue : current.trim();
    return '$label: $previousText → $currentText';
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
