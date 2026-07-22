import 'package:flutter/material.dart';

import '../entities/prescription_change_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: prescription_change_radar_ui_boundary.dart
// 역할: 최근 관련 처방과 현재 처방의 변화 비교 결과를 카드 형태로 표시한다.

// 클래스명: PrescriptionChangeRadarUI
// 역할: 처방 구성과 복약 일정의 객관적 변화를 분석 결과 상단에 보여준다.
// 주요 책임:
// - 관련 처방 존재 여부, 비교 기준일과 비교 생략 이유를 표시한다.
// - 추가, 이번 처방 미확인, 복약 일정 변경을 구분해 표시한다.
// - 변화 정보가 복용 중단 지시가 아님을 사용자에게 안내한다.
class PrescriptionChangeRadarUI extends StatelessWidget {
  final PrescriptionChangeRadar radar;
  final UserSetting userSetting;

  const PrescriptionChangeRadarUI({
    super.key,
    required this.radar,
    required this.userSetting,
  });

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
// 역할: 결과 화면을 막지 않고 처방 변화 비교가 진행 중임을 표시한다.
class PrescriptionChangeRadarLoadingUI extends StatelessWidget {
  final UserSetting userSetting;

  const PrescriptionChangeRadarLoadingUI({
    super.key,
    required this.userSetting,
  });

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
// 역할: 처방 변화 레이더의 제목과 기능 설명을 표시한다.
class _RadarHeader extends StatelessWidget {
  final _PrescriptionChangeText text;
  final double scale;
  final int comparisonWindowDays;

  const _RadarHeader({
    required this.text,
    required this.scale,
    required this.comparisonWindowDays,
  });

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
// 역할: 추가, 일정 변경, 미확인 개수를 색상별 요약 표식으로 표시한다.
class _ChangeSummary extends StatelessWidget {
  final PrescriptionChangeSummary summary;
  final _PrescriptionChangeText text;
  final double scale;

  const _ChangeSummary({
    required this.summary,
    required this.text,
    required this.scale,
  });

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
// 역할: 처방 변화 유형 한 건의 개수 표식을 표시한다.
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final double scale;

  const _SummaryChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.scale,
  });

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
// 역할: 약품 한 건의 변화 유형과 변경 전후 일정 값을 표시한다.
class _MedicationChangeRow extends StatelessWidget {
  final PrescriptionMedicationChange change;
  final _PrescriptionChangeText text;
  final double scale;

  const _MedicationChangeRow({
    required this.change,
    required this.text,
    required this.scale,
  });

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
// 역할: 이전 처방과 달라진 점이 없을 때 안정적인 빈 상태를 표시한다.
class _NoChangeMessage extends StatelessWidget {
  final _PrescriptionChangeText text;
  final double scale;

  const _NoChangeMessage({required this.text, required this.scale});

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
// 역할: 처방 변화 유형을 화면 아이콘, 색상, 문구로 변환한다.
class _ChangePresentation {
  final IconData icon;
  final Color color;
  final String label;

  const _ChangePresentation({
    required this.icon,
    required this.color,
    required this.label,
  });

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
// 역할: 처방 변화 레이더의 한국어와 영어 문구를 제공한다.
class _PrescriptionChangeText {
  final String language;

  const _PrescriptionChangeText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get title => isEnglish ? 'Prescription Change Radar' : '처방 변화 레이더';
  String subtitle(int windowDays) => isEnglish
      ? 'Compared with a related prescription from the last $windowDays days'
      : '최근 $windowDays일의 관련 처방과 비교해요';
  String get noPreviousPrescription => isEnglish
      ? 'There is no previous prescription to compare yet. Save this prescription to use it as a baseline next time.'
      : '아직 비교할 이전 처방이 없습니다. 이번 처방을 저장하면 다음 처방부터 변화를 확인할 수 있어요.';
  String get loading => isEnglish
      ? 'Comparing with your previous prescription...'
      : '이전 처방과 달라진 점을 확인하고 있어요...';
  String get noChanges => isEnglish
      ? 'No medication or schedule changes were found.'
      : '약품 구성과 복약 일정에서 달라진 점을 찾지 못했습니다.';
  String get added => isEnglish ? 'Newly found' : '새롭게 확인됨';
  String get missing =>
      isEnglish ? 'Not found in this prescription' : '이번 처방에서 확인되지 않음';
  String get scheduleChanged => isEnglish ? 'Schedule changed' : '복약 일정 변경';
  String get unknownChange => isEnglish ? 'Change found' : '변화 확인';
  String get unknownMedication =>
      isEnglish ? 'Medication name unavailable' : '약품명 확인 필요';
  String get safetyNotice => isEnglish
      ? 'This comparison is not an instruction to start or stop medication. Confirm changes with the prescription or a healthcare professional.'
      : '이 비교는 복용 시작·중단 지시가 아닙니다. 실제 변경 여부는 처방전이나 의료진을 통해 확인해주세요.';

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

  String addedCount(int count) => isEnglish ? 'Added $count' : '추가 $count';
  String changedCount(int count) =>
      isEnglish ? 'Changed $count' : '일정 변경 $count';
  String missingCount(int count) =>
      isEnglish ? 'Not found $count' : '미확인 $count';

  String comparisonPeriod(DateTime? previous, DateTime? current) {
    final previousText = _formatDate(previous);
    final currentText = _formatDate(current);
    return isEnglish
        ? 'Comparison: $previousText → $currentText'
        : '비교 기준: $previousText → $currentText';
  }

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
