import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'viewmodels/medication_viewmodel.dart';
import 'views/home_screen.dart';

void main() {
  runApp(const MedBuddyApp());
}

class MedBuddyApp extends StatelessWidget {
  const MedBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MedicationViewModel()),
      ],
      child: MaterialApp(
        title: 'MedBuddy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF009966),
          ),
          primaryColor: const Color(0xFF009966),
          scaffoldBackgroundColor: const Color(0xFFF4FFF4),
          useMaterial3: true,
          fontFamilyFallback: const ['Noto Sans KR', 'Roboto', 'Arial'],
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
