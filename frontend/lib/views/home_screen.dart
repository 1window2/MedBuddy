import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/medication_viewmodel.dart';
import 'pillbox_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Color _primary = Color(0xFF009966);
  static const Color _primaryDark = Color(0xFF007A55);
  static const Color _mint = Color(0xFFD0FAE5);
  static const Color _pageBg = Color(0xFFF4FFF4);
  static const Color _textStrong = Color(0xFF101828);
  static const Color _textMuted = Color(0xFF6A7282);

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedicationViewModel>();

    if (viewModel.isLoading) {
      return _buildLoadingScreen(viewModel);
    }

    if (viewModel.parsedDrugList.isNotEmpty) {
      return _buildAnalysisResultScreen(context, viewModel);
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHomeHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(42, 10, 42, 24),
                child: Column(
                  children: [
                    _buildScheduleCard(viewModel.statusMessage),
                    const SizedBox(height: 20),
                    _buildHomeActionCard(
                      icon: Icons.camera_alt_outlined,
                      title: '처방전 촬영하기',
                      subtitle: '카메라로 처방전을 찍어주세요',
                      filled: true,
                      onTap: viewModel.processMedicationImage,
                    ),
                    const SizedBox(height: 22),
                    _buildHomeActionCard(
                      icon: Icons.medication_outlined,
                      title: '저장된 복약 정보',
                      subtitle: '저장된 복약 정보 확인',
                      filled: false,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PillboxScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 42),
                    _buildPageIndicator(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeHeader() {
    return Container(
      height: 132,
      width: double.infinity,
      color: _primary,
      padding: const EdgeInsets.fromLTRB(48, 44, 34, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
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
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(String statusMessage) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 171),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.4),
        border: Border.all(color: _mint, width: 2.7),
        boxShadow: _softShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.schedule_outlined, color: _primary, size: 46),
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
              color: Color(0xFF99A1AF),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final background = filled ? _primary : Colors.white;
    final foreground = filled ? Colors.white : _primaryDark;
    final secondary = filled ? _mint : _primary;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14.4),
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.4),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: filled ? 176 : 182,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.4),
            border: filled ? null : Border.all(color: _mint, width: 2.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 44),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  color: foreground,
                  fontSize: 21.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondary,
                  fontSize: 14.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 28.8,
          height: 7.2,
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(999),
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
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingScreen(MedicationViewModel viewModel) {
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
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 22,
                  offset: const Offset(0, 16),
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
                    color: _primary,
                    strokeWidth: 7,
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  '처방전 인식 중...',
                  style: TextStyle(
                    color: _textStrong,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  viewModel.statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 10,
                    color: _primary,
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

  Widget _buildAnalysisResultScreen(
    BuildContext context,
    MedicationViewModel viewModel,
  ) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildResultHeader(),
            _buildAnalysisSummary(viewModel.parsedDrugList.length),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
                itemCount: viewModel.parsedDrugList.length,
                itemBuilder: (context, index) {
                  final drug =
                      viewModel.parsedDrugList[index] as Map<String, dynamic>;
                  return _buildParsedDrugCard(context, viewModel, drug);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultHeader() {
    return Container(
      height: 94,
      width: double.infinity,
      color: _primary,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 22),
      child: const Text(
        '처방전 분석 결과',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAnalysisSummary(int count) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA4F4CF), width: 2),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  '분석 완료',
                  style: TextStyle(
                    color: _primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count개의 약물 정보를 찾았습니다',
                  style: const TextStyle(
                    color: Color(0xFF4A5565),
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

  Widget _buildParsedDrugCard(
    BuildContext context,
    MedicationViewModel viewModel,
    Map<String, dynamic> drug,
  ) {
    final drugName = _textValue(drug['drug_name']);
    final dosage = _textValue(drug['dosage_per_time']);
    final frequency = _textValue(drug['daily_frequency']);
    final days = _textValue(drug['total_days']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
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
                    drugName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textStrong,
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
                _buildDoseInfoRow(
                  icon: Icons.medication_liquid_outlined,
                  label: '1회 투약량',
                  value: dosage,
                ),
                const SizedBox(height: 14),
                _buildDoseInfoRow(
                  icon: Icons.schedule_outlined,
                  label: '1일 횟수',
                  value: frequency,
                ),
                const SizedBox(height: 14),
                _buildDoseInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: '총 투약일',
                  value: days,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final success = await viewModel.analyzeAndSave(drug);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(viewModel.statusMessage),
                            backgroundColor: success
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.analytics_outlined, size: 20),
                    label: const Text('상세 분석 & 약통에 저장'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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

  Widget _buildDoseInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: _primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4A5565),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: _primaryDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  String _textValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '정보 없음' : text;
  }

  List<BoxShadow> get _softShadow => [
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, 0.12),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ];
}
