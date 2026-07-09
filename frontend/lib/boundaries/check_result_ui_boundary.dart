import 'package:flutter/material.dart';

import '../entities/analyzed_medication_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: check_result_ui_boundary.dart
// 역할: 공공데이터 분석이 끝난 처방전 결과 목록 화면을 구성한다.

// 클래스명: CheckResultUI
// 역할: 분석된 약 목록과 복약 일정 정보를 보여주고 사용자가 항목별 저장을 실행하게 한다.
// 주요 책임:
// - 분석된 약 개수와 각 약의 복약 스케줄을 표시한다.
// - 저장 버튼의 개별 로딩 상태를 보여준다.
// - 전체 저장과 저장 완료 항목 비활성화 상태를 제공한다.
// - 저장 결과를 Snackbar로 사용자에게 알린다.
class CheckResultUI extends StatelessWidget {
  final List<AnalyzedMedication> analyzedMedicationList;
  final UserSetting userSetting;
  final String Function() statusMessageProvider;
  final int? savingMedicationIndex;
  final Set<int> completedMedicationSaveIndexes;
  final bool isAllMedicationSaving;
  final VoidCallback onCloseRequested;
  final Future<bool> Function() onAllMedicationSaveRequested;
  final Future<bool> Function(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) onMedicationSaveRequested;

  const CheckResultUI({
    super.key,
    required this.analyzedMedicationList,
    required this.userSetting,
    required this.statusMessageProvider,
    required this.savingMedicationIndex,
    required this.completedMedicationSaveIndexes,
    required this.isAllMedicationSaving,
    required this.onCloseRequested,
    required this.onAllMedicationSaveRequested,
    required this.onMedicationSaveRequested,
  });

  @override
  Widget build(BuildContext context) {
    final text = _ResultText(userSetting.language);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ResultHeader(
              title: text.title,
              backTooltip: text.back,
              onCloseRequested: onCloseRequested,
            ),
            _AnalysisSummary(
              count: analyzedMedicationList.length,
              text: text,
              userSetting: userSetting,
            ),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(40, 10, 40, 126),
                    itemCount: analyzedMedicationList.length,
                    itemBuilder: (context, index) {
                      final analyzedMedication = analyzedMedicationList[index];
                      return _MedicationResultCard(
                        analyzedMedication: analyzedMedication,
                        text: text,
                        userSetting: userSetting,
                        isMedicationSaving: savingMedicationIndex == index,
                        isMedicationSaved:
                            completedMedicationSaveIndexes.contains(index),
                        isAllMedicationSaving: isAllMedicationSaving,
                        onMedicationSaveRequested: () async {
                          final success = await onMedicationSaveRequested(
                            analyzedMedication,
                            index,
                          );
                          if (!context.mounted) {
                            return;
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(statusMessageProvider()),
                              backgroundColor: success
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _BulkSaveButton(
                      text: text,
                      userSetting: userSetting,
                      isSaving: isAllMedicationSaving,
                      isCompleted: completedMedicationSaveIndexes.length >=
                          analyzedMedicationList.length,
                      onPressed: () async {
                        final success = await onAllMedicationSaveRequested();
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(statusMessageProvider()),
                            backgroundColor: success
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final String title;
  final String backTooltip;
  final VoidCallback onCloseRequested;

  const _ResultHeader({
    required this.title,
    required this.backTooltip,
    required this.onCloseRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: backTooltip,
            onPressed: onCloseRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  final int count;
  final _ResultText text;
  final UserSetting userSetting;

  const _AnalysisSummary({
    required this.count,
    required this.text,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.successBorder, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: MedBuddyColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.complete,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  text.summary(count),
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14 * scale,
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

class _BulkSaveButton extends StatelessWidget {
  final _ResultText text;
  final UserSetting userSetting;
  final bool isSaving;
  final bool isCompleted;
  final Future<void> Function() onPressed;

  const _BulkSaveButton({
    required this.text,
    required this.userSetting,
    required this.isSaving,
    required this.isCompleted,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        40,
        22,
        40,
        MediaQuery.of(context).padding.bottom + 23,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: isSaving || isCompleted ? null : () async => onPressed(),
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isCompleted ? Icons.check_circle_outline : Icons.done_all,
                  size: 22,
                ),
          label: Text(
            isCompleted
                ? text.allSaved
                : isSaving
                    ? text.savingAll
                    : text.saveAll,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: MedBuddyColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF9CA3AF),
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(66),
            shape: RoundedRectangleBorder(
              borderRadius: MedBuddyRadii.largeCard,
            ),
            textStyle: TextStyle(
              fontSize: 22 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicationResultCard extends StatelessWidget {
  final AnalyzedMedication analyzedMedication;
  final _ResultText text;
  final UserSetting userSetting;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onMedicationSaveRequested;

  const _MedicationResultCard({
    required this.analyzedMedication,
    required this.text,
    required this.userSetting,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onMedicationSaveRequested,
  });

  @override
  Widget build(BuildContext context) {
    final schedule = analyzedMedication.schedule;
    final scale = userSetting.contentTextScale;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.cardBorder, width: 2),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: MedBuddyColors.mint, width: 2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MedBuddyColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    analyzedMedication.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _MedicationSaveIconButton(
                  text: text,
                  isMedicationSaving: isMedicationSaving,
                  isMedicationSaved: isMedicationSaved,
                  isAllMedicationSaving: isAllMedicationSaving,
                  onPressed: onMedicationSaveRequested,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                _DoseInfoRow(
                  icon: Icons.medication_liquid_outlined,
                  label: text.dose,
                  value: _displayValue(schedule.dosage),
                  userSetting: userSetting,
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.schedule_outlined,
                  label: text.frequency,
                  value: _displayValue(schedule.intakeTime),
                  userSetting: userSetting,
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: text.duration,
                  value: _displayValue(schedule.medicationTimeLabel),
                  userSetting: userSetting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayValue(String value, {int? maxLength}) {
    final textValue = value.trim().isEmpty ? text.noInformation : value.trim();
    if (maxLength == null || textValue.length <= maxLength) {
      return textValue;
    }
    return '${textValue.substring(0, maxLength)}...';
  }
}

class _MedicationSaveIconButton extends StatelessWidget {
  final _ResultText text;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onPressed;

  const _MedicationSaveIconButton({
    required this.text,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled =
        isMedicationSaving || isMedicationSaved || isAllMedicationSaving;

    return Tooltip(
      message: isMedicationSaved ? text.saved : text.saveSchedule,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        style: IconButton.styleFrom(
          foregroundColor: MedBuddyColors.primary,
          disabledForegroundColor: MedBuddyColors.textLight,
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
        ),
        onPressed: isDisabled ? null : () async => onPressed(),
        icon: isMedicationSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: MedBuddyColors.primary,
                ),
              )
            : Icon(
                isMedicationSaved
                    ? Icons.check_circle_outline
                    : Icons.edit_outlined,
                size: 22,
              ),
      ),
    );
  }
}

class _DoseInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final UserSetting userSetting;

  const _DoseInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Row(
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 15 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: MedBuddyColors.mint,
            borderRadius: MedBuddyRadii.pill,
          ),
          child: Text(
            value,
            style: TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 15 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultText {
  final String language;

  const _ResultText(this.language);

  bool get isEnglish => language == 'en';

  String get title => isEnglish ? 'Prescription Analysis Result' : '처방전 분석 결과';
  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get complete => isEnglish ? 'Analysis Complete' : '분석 완료';
  String summary(int count) => isEnglish
      ? '$count medication item${count == 1 ? '' : 's'} ready to save'
      : '$count개의 복약 일정을 저장할 수 있습니다';
  String get dose => isEnglish ? 'Dose' : '1회 투약량';
  String get frequency => isEnglish ? 'Frequency' : '1일 횟수';
  String get duration => isEnglish ? 'Duration' : '총 투약일';
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  String get saveAll => isEnglish ? 'Save All' : '전체 저장하기';
  String get savingAll => isEnglish ? 'Saving all...' : '전체 저장 중...';
  String get allSaved => isEnglish ? 'All Saved' : '전체 저장 완료';
  String get saveSchedule =>
      isEnglish ? 'Save Medication Schedule' : '복약 일정 저장하기';
  String get saved => isEnglish ? 'Saved' : '저장 완료';
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
}
