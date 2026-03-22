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
    // 화면이 켜지자마자 백엔드에서 약통 목록을 싹 가져와!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MedicationViewModel>(context, listen: false).fetchPillbox();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<MedicationViewModel>(context);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('내 약통 💊'),
        backgroundColor: Colors.blue[50],
      ),
      body: viewModel.savedDrugs.isEmpty
          ? Center(child: Text('약통이 비어있어요!\n홈 화면에서 약을 추가해 보세요.', textAlign: TextAlign.center))
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: viewModel.savedDrugs.length,
              itemBuilder: (context, index) {
                final drug = viewModel.savedDrugs[index];
                return Card(
                  margin: EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    title: Text(drug.itemName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0), // 👈 에러의 원인이었던 치명적 오타 수정 완!
                      child: Text(drug.aiGuide ?? 'AI 요약 정보가 없습니다.', style: TextStyle(color: Colors.blue[800])),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                      onPressed: () {
                        if (drug.id != null) {
                          viewModel.removeDrugFromPillbox(drug.id!);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('삭제되었습니다.'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}