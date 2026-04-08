import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/medication_viewmodel.dart';

class PillboxScreen extends StatefulWidget {
  const PillboxScreen({super.key}); // 파란줄(Lint) 해결

  @override
  State<PillboxScreen> createState() => _PillboxScreenState(); // 파란줄 해결
}

class _PillboxScreenState extends State<PillboxScreen> {
  @override
  void initState() {
    super.initState();
    // backend에서 pillbox fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MedicationViewModel>(context, listen: false).fetchPillbox();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<MedicationViewModel>(context);
    final savedDrugs = viewModel.savedDrugs;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('내 약통 💊', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[50],
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: savedDrugs.isEmpty
          ? _buildEmptyState() // if pillbox empty
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: savedDrugs.length,
              itemBuilder: (context, index) {
                final drug = savedDrugs[index];
                return _buildDrugCard(context, viewModel, drug);
              },
            ),
    );
  }

  // 1. Initial State, Empty State
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_liquid, size: 80, color: Colors.grey[300]),
          SizedBox(height: 16),
          Text(
            '약통이 비어있어요!',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '홈 화면에서 처방전을 분석하고\n나만의 약통에 저장해 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // 2. Saved Medication UI (+ AI 가이드 박스)
  Widget _buildDrugCard(BuildContext context, MedicationViewModel viewModel, dynamic drug) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [상단] 약 이름 / 삭제 버튼
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue[100], shape: BoxShape.circle),
                  child: Icon(Icons.medication, color: Colors.blue[800], size: 24),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    drug.itemName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                  onPressed: () {
                    if (drug.id != null) {
                      viewModel.removeDrugFromPillbox(drug.id!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${drug.itemName}이(가) 삭제되었습니다.'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
                ),
              ],
            ),
            Divider(height: 24, color: Colors.grey[200]),

            // [중단] 공공DB 기반 기본 정보
            _buildInfoRow('효능', drug.efficacy),
            SizedBox(height: 8),
            _buildInfoRow('용법', drug.useMethod),
            SizedBox(height: 16),

            // [하단] AI 가이드
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.health_and_safety, color: Colors.green[700], size: 20),
                      SizedBox(width: 8),
                      Text('AI 친절한 약사 가이드', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    drug.aiGuide ?? 'AI 요약 정보가 없습니다.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. 헬퍼 Widget
  Widget _buildInfoRow(String label, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            content.length > 50 ? '${content.substring(0, 50)}...' : content, // 원본이 너무 길면 후략
            style: TextStyle(color: Colors.black87),
          ),
        ),
      ],
    );
  }
}