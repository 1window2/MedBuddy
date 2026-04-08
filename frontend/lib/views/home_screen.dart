import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/medication_viewmodel.dart';
import 'pillbox_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedicationViewModel>();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('MedBuddy AI 비전 인식', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[50],
        actions: [
          IconButton(
            icon: Icon(Icons.medication, color: Colors.blue[800]),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PillboxScreen()),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 상태 메시지 
            Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(child: Text(viewModel.statusMessage, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            SizedBox(height: 20),
            
            // 로딩 스피너
            if (viewModel.isLoading) 
              Expanded(child: Center(child: CircularProgressIndicator(color: Colors.blue)))
            
            // 결과 화면 (병원 정보 + 약 리스트)
            else if (viewModel.parsedDrugList.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 병원/조제 정보 카드
                    Card(
                      color: Colors.blue[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(viewModel.hospitalName, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('조제 일자: ${viewModel.prescriptionDate}', style: TextStyle(color: Colors.blue[100], fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text('추출된 약품 목록 (${viewModel.parsedDrugList.length}건)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    SizedBox(height: 8),

                    // 약 리스트
                    Expanded(
                      child: ListView.builder(
                        itemCount: viewModel.parsedDrugList.length,
                        itemBuilder: (context, index) {
                          final drug = viewModel.parsedDrugList[index];
                          return Card(
                            elevation: 1,
                            margin: EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.medication_liquid, color: Colors.blue[400]),
                                      SizedBox(width: 8),
                                      Expanded(child: Text(drug['drug_name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                  Divider(height: 24, color: Colors.grey[200]),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildInfoBadge('1회 투약량', drug['dosage_per_time']),
                                      _buildInfoBadge('1일 횟수', drug['daily_frequency']),
                                      _buildInfoBadge('총 투약일', drug['total_days']),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  // 실제 작동하는 저장 버튼
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue[800], // 버튼 색상을 조금 더 강조
                                        backgroundColor: Colors.blue[50],
                                      ),
                                      onPressed: () async {
                                        // 1. ViewModel의 분석 및 저장 파이프라인 가동!
                                        bool success = await viewModel.analyzeAndSave(drug);

                                        // 2. 완료 후 하단에 스낵바 알림 띄우기
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(viewModel.statusMessage),
                                              backgroundColor: success ? Colors.green[600] : Colors.red[400],
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                      icon: Icon(Icons.analytics, size: 18),
                                      label: Text('상세 분석 & 약통에 저장'),
                                    ),
                                  )
                                ],
                              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => viewModel.processMedicationImage(),
        icon: Icon(Icons.camera_alt),
        label: Text('처방전 촬영'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
    );
  }

  // badge widget 헬퍼 함수
  Widget _buildInfoBadge(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20)),
          child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[800])),
        ),
      ],
    );
  }
}