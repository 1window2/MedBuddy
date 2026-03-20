import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/medication_viewmodel.dart';

class HomeScreen extends StatelessWidget {
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
                      child: ListTile(
                        title: Text(drug.itemName, style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(drug.efficacy, maxLines: 2, overflow: TextOverflow.ellipsis),
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