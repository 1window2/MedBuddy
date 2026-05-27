import 'package:flutter/material.dart';

import '../models/medication_candidate.dart';
import '../theme/medbuddy_theme.dart';

class PrescriptionResultUI extends StatelessWidget {
  final List<MedicationCandidate> medicationCandidates;
  final String Function() statusMessageProvider;
  final bool isMedicationSaving;
  final VoidCallback onCloseRequested;
  final Future<bool> Function(MedicationCandidate medicationCandidate)
      onMedicationSaveRequested;

  const PrescriptionResultUI({
    super.key,
    required this.medicationCandidates,
    required this.statusMessageProvider,
    required this.isMedicationSaving,
    required this.onCloseRequested,
    required this.onMedicationSaveRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ResultHeader(onCloseRequested: onCloseRequested),
            _AnalysisSummary(count: medicationCandidates.length),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
                itemCount: medicationCandidates.length,
                itemBuilder: (context, index) {
                  final medicationCandidate = medicationCandidates[index];
                  return _MedicationCandidateCard(
                    medicationCandidate: medicationCandidate,
                    isMedicationSaving: isMedicationSaving,
                    onMedicationSaveRequested: () async {
                      final success = await onMedicationSaveRequested(
                        medicationCandidate,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final VoidCallback onCloseRequested;

  const _ResultHeader({required this.onCloseRequested});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onCloseRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const Expanded(
            child: Text(
              '처방전 분석 결과',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
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

  const _AnalysisSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFA4F4CF), width: 2),
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
                const Text(
                  '분석 완료',
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count개의 약물 정보를 찾았습니다',
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
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

class _MedicationCandidateCard extends StatelessWidget {
  final MedicationCandidate medicationCandidate;
  final bool isMedicationSaving;
  final Future<void> Function() onMedicationSaveRequested;

  const _MedicationCandidateCard({
    required this.medicationCandidate,
    required this.isMedicationSaving,
    required this.onMedicationSaveRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
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
                    medicationCandidate.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
                  label: '1회 투약량',
                  value: _displayValue(medicationCandidate.dosagePerTime),
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.schedule_outlined,
                  label: '1일 횟수',
                  value: _displayValue(medicationCandidate.dailyFrequency),
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: '총 투약일',
                  value: _displayValue(medicationCandidate.totalDays),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isMedicationSaving
                        ? null
                        : () async => onMedicationSaveRequested(),
                    icon: isMedicationSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.analytics_outlined, size: 20),
                    label: Text(
                      isMedicationSaving ? '분석 및 저장 중' : '상세 분석 & 약통에 저장',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          MedBuddyColors.primary.withValues(alpha: 0.65),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: MedBuddyRadii.card,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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

  String _displayValue(String value) {
    return value.trim().isEmpty ? '정보 없음' : value.trim();
  }
}

class _DoseInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DoseInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
            style: const TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
