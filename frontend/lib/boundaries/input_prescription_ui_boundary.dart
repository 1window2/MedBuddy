import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

class InputPrescriptionUI extends StatelessWidget {
  final String statusMessage;
  final VoidCallback? onPrescriptionScanRequested;
  final VoidCallback? onPrescriptionGalleryRequested;
  final VoidCallback? onSavedMedicationRequested;
  final bool isAnalyzing;

  const InputPrescriptionUI({
    super.key,
    required this.statusMessage,
    required this.onPrescriptionScanRequested,
    required this.onPrescriptionGalleryRequested,
    required this.onSavedMedicationRequested,
  }) : isAnalyzing = false;

  const InputPrescriptionUI.analyzing({
    super.key,
    required this.statusMessage,
  })  : onPrescriptionScanRequested = null,
        onPrescriptionGalleryRequested = null,
        onSavedMedicationRequested = null,
        isAnalyzing = true;

  @override
  Widget build(BuildContext context) {
    if (isAnalyzing) {
      return _buildAnalyzingScreen();
    }

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
                      onTap: () => _showPrescriptionInputOptions(context),
                    ),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      icon: Icons.medication_outlined,
                      title: '저장된 복약 정보',
                      subtitle: '저장된 복약 정보 확인',
                      filled: false,
                      onTap: onSavedMedicationRequested!,
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

  void clickPrescriptionInput() {
    onPrescriptionScanRequested?.call();
  }

  void clickPrescriptionImageSelect() {
    onPrescriptionGalleryRequested?.call();
  }

  String showMaskedInfrmation() {
    return statusMessage;
  }

  void _showPrescriptionInputOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DC),
                    borderRadius: MedBuddyRadii.pill,
                  ),
                ),
                const SizedBox(height: 18),
                _PrescriptionInputOption(
                  icon: Icons.camera_alt_outlined,
                  title: '카메라로 촬영',
                  subtitle: '약봉투나 처방전을 바로 촬영합니다.',
                  onTap: () {
                    Navigator.pop(context);
                    onPrescriptionScanRequested?.call();
                  },
                ),
                const SizedBox(height: 10),
                _PrescriptionInputOption(
                  icon: Icons.photo_library_outlined,
                  title: '갤러리에서 선택',
                  subtitle: '저장된 약봉투 이미지를 불러옵니다.',
                  onTap: () {
                    Navigator.pop(context);
                    onPrescriptionGalleryRequested?.call();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalyzingScreen() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFECFDF5), Colors.white],
          ),
        ),
        child: Center(
          child: Container(
            width: 328,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD1D5DC), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 22,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    color: MedBuddyColors.primary,
                    strokeWidth: 7,
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  '처방전 인식 중...',
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6A7282),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                ClipRRect(
                  borderRadius: MedBuddyRadii.pill,
                  child: const LinearProgressIndicator(
                    minHeight: 10,
                    color: MedBuddyColors.primary,
                    backgroundColor: Color(0xFFE5E7EB),
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

class _PrescriptionInputOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PrescriptionInputOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4FFF4),
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: MedBuddyColors.primary,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
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
