import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../entities/medication_detail_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

class CheckSavedMedicationUI extends StatefulWidget {
  const CheckSavedMedicationUI({super.key});

  void clickSavedMedicationInfo() {}

  void selectMedicationInfo() {}

  void showSavedMedicationInfo() {}

  void showUpdatedMedicationInfo() {}

  @override
  State<CheckSavedMedicationUI> createState() => _CheckSavedMedicationUIState();
}

class _CheckSavedMedicationUIState extends State<CheckSavedMedicationUI> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MedBuddyViewModel>().fetchSavedMedicationInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();
    final savedMedicationInfoList = viewModel.savedMedicationInfoList;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _SavedMedicationHeader(
                onBackRequested: () => Navigator.pop(context)),
            if (savedMedicationInfoList.isNotEmpty)
              _SavedMedicationSummary(count: savedMedicationInfoList.length),
            Expanded(
              child: _buildContent(viewModel, savedMedicationInfoList),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    MedBuddyViewModel viewModel,
    List<MedicationDetail> savedMedicationInfoList,
  ) {
    if (viewModel.isSavedMedicationLoading && savedMedicationInfoList.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    if (savedMedicationInfoList.isEmpty) {
      return const _SavedMedicationEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
      itemCount: savedMedicationInfoList.length,
      itemBuilder: (context, index) {
        final savedMedicationInfo = savedMedicationInfoList[index];
        return _SavedMedicationCard(
          savedMedicationInfo: savedMedicationInfo,
          onDeleteRequested: () async {
            final success = await viewModel.requestDeleteSavedMedication(
              savedMedicationInfo.id!,
            );
            if (!context.mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? '${savedMedicationInfo.itemName}이(가) 삭제되었습니다.'
                      : '삭제에 실패했습니다.',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }
}

class _SavedMedicationHeader extends StatelessWidget {
  final VoidCallback onBackRequested;

  const _SavedMedicationHeader({required this.onBackRequested});

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
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const Expanded(
            child: Text(
              '저장된 복약 정보',
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

class _SavedMedicationSummary extends StatelessWidget {
  final int count;

  const _SavedMedicationSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 0),
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
                  '저장 완료',
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count개의 복약 정보를 보관 중입니다',
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

class _SavedMedicationEmptyState extends StatelessWidget {
  const _SavedMedicationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 328,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          border: Border.all(color: MedBuddyColors.mint, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.10),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 54,
              color: MedBuddyColors.primary,
            ),
            SizedBox(height: 18),
            Text(
              '저장된 약이 없습니다',
              style: TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '홈 화면에서 처방전을 분석하고\n약통에 저장해 보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedBuddyColors.textLight,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMedicationCard extends StatelessWidget {
  final MedicationDetail savedMedicationInfo;
  final Future<void> Function() onDeleteRequested;

  const _SavedMedicationCard({
    required this.savedMedicationInfo,
    required this.onDeleteRequested,
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
                    _displayValue(savedMedicationInfo.itemName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: MedBuddyColors.primary,
                  ),
                  onPressed: onDeleteRequested,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                _InfoBlock(
                  icon: Icons.info_outline,
                  label: '효능',
                  content: savedMedicationInfo.efficacy,
                ),
                const SizedBox(height: 14),
                _InfoBlock(
                  icon: Icons.schedule_outlined,
                  label: '복용 방법',
                  content: savedMedicationInfo.usageMethod,
                ),
                const SizedBox(height: 14),
                _InfoBlock(
                  icon: Icons.warning_amber_outlined,
                  label: '주의사항',
                  content: savedMedicationInfo.warning,
                ),
                const SizedBox(height: 16),
                _AiGuide(aiGuide: savedMedicationInfo.aiGuide),
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

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String content;

  const _InfoBlock({
    required this.icon,
    required this.label,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _shorten(content),
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiGuide extends StatelessWidget {
  final String aiGuide;

  const _AiGuide({required this.aiGuide});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: MedBuddyColors.infoBlue,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'AI 복약 가이드',
                style: TextStyle(
                  color: MedBuddyColors.infoBlue,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _shorten(aiGuide, maxLength: 90),
            style: const TextStyle(
              color: MedBuddyColors.infoBlue,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

String _shorten(String content, {int maxLength = 72}) {
  final text = content.trim().isEmpty ? '정보 없음' : content.trim();
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}
