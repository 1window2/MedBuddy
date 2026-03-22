import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 우리가 만든 화면과 뷰모델을 불러와
import 'views/home_screen.dart';
import 'viewmodels/medication_viewmodel.dart';

// 1. 앱의 진입점 (엔진 시동)
void main() {
  // runApp()은 주어진 위젯을 화면에 그리는 Flutter의 핵심 함수야.
  runApp(const MedBuddyApp());
}

// 2. 앱의 최상위 루트 구조 
class MedBuddyApp extends StatelessWidget {
  const MedBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 3. 의존성 주입 및 상태 관리 환경 세팅 (GameManager 역할)
    return MultiProvider(
      providers: [
        // MedicationViewModel을 앱 전체에서 쓸 수 있도록 최상단에 등록해.
        // 이제 하위 화면 어디서든 백엔드와 통신하는 이 ViewModel에 접근할 수 있어.
        ChangeNotifierProvider(create: (_) => MedicationViewModel()),
      ],
      
      // 4. 머티리얼 앱 디자인 및 초기 화면 설정
      child: MaterialApp(
        title: 'MedBuddy',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        // 앱이 켜지자마자 보여줄 첫 화면을 우리가 만든 HomeScreen으로 지정!
        home: HomeScreen(), 
      ),
    );
  }
}