import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drug_info.dart';
import '../viewmodels/medication_viewmodel.dart';

class PillboxScreen extends StatefulWidget {
  const PillboxScreen({super.key});

  @override
  State<PillboxScreen> createState() => _PillboxScreenState();
}

class _PillboxScreenState extends State<PillboxScreen> {
  static const Color _primary = Color(0xFF009966);
  static const Color _primaryDark = Color(0xFF007A55);
  static const Color _mint = Color(0xFFD0FAE5);
  static const Color _textStrong = Color(0xFF101828);
  static const Color _textMuted = Color(0xFF4A5565);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MedicationViewModel>(context, listen: false).fetchPillbox();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<MedicationViewModel>(context);
    final savedDrugs = viewModel.savedDrugs;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            if (savedDrugs.isNotEmpty) _buildSummary(savedDrugs.length),
            Expanded(
              child: savedDrugs.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
                      itemCount: savedDrugs.length,
                      itemBuilder: (context, index) {
                        final drug = savedDrugs[index];
                        return _buildDrugCard(context, viewModel, drug);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      width: double.infinity,
      color: _primary,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
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

  Widget _buildSummary(int count) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
              color: _mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: _primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '저장 완료',
                  style: TextStyle(
                    color: _primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count개의 복약 정보를 보관 중입니다',
                  style: const TextStyle(color: _textMuted, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: 328,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _mint, width: 2),
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
            Icon(Icons.medication_outlined, size: 54, color: _primary),
            SizedBox(height: 18),
            Text(
              '저장된 약이 없습니다',
              style: TextStyle(
                color: _textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '홈 화면에서 처방전을 분석하고\n약통에 저장해 보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF99A1AF),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrugCard(
    BuildContext context,
    MedicationViewModel viewModel,
    DrugInfo drug,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.12),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
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
                bottom: BorderSide(color: _mint, width: 2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _primary,
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
                    drug.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textStrong,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _primary),
                  onPressed: () {
                    if (drug.id != null) {
                      viewModel.removeDrugFromPillbox(drug.id!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${drug.itemName}이(가) 삭제되었습니다.'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                _buildInfoBlock(
                  icon: Icons.info_outline,
                  label: '효능',
                  content: drug.efficacy,
                ),
                const SizedBox(height: 14),
                _buildInfoBlock(
                  icon: Icons.schedule_outlined,
                  label: '복용 방법',
                  content: drug.useMethod,
                ),
                const SizedBox(height: 14),
                _buildInfoBlock(
                  icon: Icons.warning_amber_outlined,
                  label: '주의사항',
                  content: drug.warningMessage,
                ),
                const SizedBox(height: 16),
                _buildAiGuide(drug.aiGuide),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBlock({
    required IconData icon,
    required String label,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _shorten(content),
                style: const TextStyle(
                  color: _textStrong,
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

  Widget _buildAiGuide(String? aiGuide) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: Color(0xFF1C398E), size: 20),
              SizedBox(width: 8),
              Text(
                'AI 복약 가이드',
                style: TextStyle(
                  color: Color(0xFF1C398E),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _shorten(aiGuide ?? 'AI 요약 정보가 없습니다.', maxLength: 90),
            style: const TextStyle(
              color: Color(0xFF1C398E),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _shorten(String content, {int maxLength = 72}) {
    final text = content.trim().isEmpty ? '정보 없음' : content.trim();
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }
}
