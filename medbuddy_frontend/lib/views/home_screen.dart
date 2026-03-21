import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/medication_viewmodel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel 상태를 구독
    final viewModel = context.watch<MedicationViewModel>();

    return Scaffold(
      appBar: AppBar(title: Text('MedBuddy 약품 인식')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(viewModel.statusMessage, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            
            // 로딩 중이면 스피너, 아니면 결과 리스트 보여주기
            if (viewModel.isLoading) 
              CircularProgressIndicator()
            else if (viewModel.drugList.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: viewModel.drugList.length,
                  itemBuilder: (context, index) {
                    final drug = viewModel.drugList[index];
                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. 약품명
                            Text(drug.itemName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            SizedBox(height: 12),
                            
                            // 2. AI 약사 가이드 (파란색 강조 박스)
                            if (drug.aiGuide != null && drug.aiGuide!.isNotEmpty)
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade100),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        drug.aiGuide!,
                                        style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(height: 12),

                            // 3. 식약처 원본 요약 (작고 연한 글씨로 표시)
                            Text("식약처 원문: ${drug.efficacy}", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey, fontSize: 12)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read<MedicationViewModel>().processMedicationImage(),
        child: Icon(Icons.camera_alt),
      ),
    );
  }
}