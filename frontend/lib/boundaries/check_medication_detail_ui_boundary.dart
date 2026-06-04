import 'package:flutter/material.dart';

class CheckMedicationDetailUI extends StatelessWidget {
  final String resultvoiceGuide;
  final String resultmedicationDetail;

  const CheckMedicationDetailUI({
    super.key,
    this.resultvoiceGuide = '',
    this.resultmedicationDetail = '',
  });

  String showMedicationDetail() {
    return resultmedicationDetail;
  }

  void clickVoiceGuide() {}

  String playVoiceGuide() {
    return resultvoiceGuide;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
