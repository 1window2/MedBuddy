import 'package:flutter/material.dart';

import '../entities/medication_detail_entity.dart';

class MedicationCandidateDialog extends StatefulWidget {
  final String originalName;
  final List<MedicationDetail> candidates;
  final bool isEnglish;

  const MedicationCandidateDialog({
    super.key,
    required this.originalName,
    required this.candidates,
    this.isEnglish = false,
  });

  @override
  State<MedicationCandidateDialog> createState() =>
      _MedicationCandidateDialogState();
}

class _MedicationCandidateDialogState extends State<MedicationCandidateDialog> {
  MedicationDetail? _selected;

  @override
  Widget build(BuildContext context) {
    final english = widget.isEnglish;
    return AlertDialog(
      title: Text(english ? 'Confirm the medication' : '약품 후보 확인'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              english
                  ? 'Prescription: ${widget.originalName}'
                  : '처방전: ${widget.originalName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              english
                  ? 'Compare the full name, strength and dosage form with your prescription. Cancel if unsure.'
                  : '처방전의 전체 약 이름·함량·제형이 같은지 확인해주세요. 확실하지 않으면 취소해주세요.',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.candidates.length; i++)
              ListTile(
                key: Key('medication-candidate-$i'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  identical(_selected, widget.candidates[i])
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                selected: identical(_selected, widget.candidates[i]),
                title: Text(widget.candidates[i].itemName),
                subtitle: Text(
                  widget.candidates[i].manufacturer.isEmpty
                      ? (english ? 'Manufacturer unavailable' : '제조사 정보 없음')
                      : widget.candidates[i].manufacturer,
                ),
                onTap: () => setState(() => _selected = widget.candidates[i]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(english ? 'Cancel' : '취소'),
        ),
        FilledButton(
          key: const Key('confirm-medication-candidate'),
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text(english ? 'Confirm this medication' : '이 약으로 확인'),
        ),
      ],
    );
  }
}
