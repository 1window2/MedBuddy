import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

class PrescriptionInputUI extends StatelessWidget {
  final String statusMessage;
  final VoidCallback onPrescriptionScanRequested;
  final VoidCallback onSavedMedicationRequested;

  const PrescriptionInputUI({
    super.key,
    required this.statusMessage,
    required this.onPrescriptionScanRequested,
    required this.onSavedMedicationRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _HomeHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(42, 10, 42, 24),
                child: Column(
                  children: [
                    _ScheduleCard(statusMessage: statusMessage),
                    const SizedBox(height: 20),
                    _HomeActionCard(
                      icon: Icons.camera_alt_outlined,
                      title: '처방전 촬영하기',
                      subtitle: '카메라로 처방전을 찍어주세요',
                      filled: true,
                      onTap: onPrescriptionScanRequested,
                    ),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      icon: Icons.medication_outlined,
                      title: '저장된 복약 정보',
                      subtitle: '저장된 복약 정보 확인',
                      filled: false,
                      onTap: onSavedMedicationRequested,
                    ),
                    const SizedBox(height: 42),
                    const _PageIndicator(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(48, 44, 34, 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEDbuddy',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 3),
          Text(
            '건강한 복약 관리 도우미',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final String statusMessage;

  const _ScheduleCard({required this.statusMessage});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 171),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.mint, width: 2.7),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.schedule_outlined,
            color: MedBuddyColors.primary,
            size: 46,
          ),
          const SizedBox(height: 10),
          const Text(
            '오늘의 복약 일정',
            style: TextStyle(
              color: Color(0xFF0A0A0A),
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textLight,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? MedBuddyColors.primary : Colors.white;
    final foreground = filled ? Colors.white : MedBuddyColors.primaryDark;
    final secondary = filled ? MedBuddyColors.mint : MedBuddyColors.primary;

    return Material(
      color: background,
      borderRadius: MedBuddyRadii.card,
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: filled ? 176 : 182),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: filled
                ? null
                : Border.all(color: MedBuddyColors.mint, width: 2.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 42),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 28.8,
          height: 7.2,
          decoration: BoxDecoration(
            color: MedBuddyColors.primary,
            borderRadius: MedBuddyRadii.pill,
          ),
        ),
        const SizedBox(width: 7.2),
        for (int index = 0; index < 2; index++)
          Container(
            width: 7.2,
            height: 7.2,
            margin: const EdgeInsets.only(right: 7.2),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DC),
              borderRadius: MedBuddyRadii.pill,
            ),
          ),
      ],
    );
  }
}
