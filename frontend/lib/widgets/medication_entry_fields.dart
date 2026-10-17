import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_dose_rhythm.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';

const medicationEntryDoseUnits = ['정', '캡슐', '포', 'mL', '방울'];

// 직접 등록과 처방 변경은 입력 요소만 공유하고 저장·기록 보존 흐름은 분리한다.
class MedicationEntrySectionTitle extends StatelessWidget {
  final String title;
  final String? optional;

  const MedicationEntrySectionTitle({
    super.key,
    required this.title,
    this.optional,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(child: Text(title, style: MedBuddyTextStyles.formSectionTitle)),
      if (optional != null) ...[
        const SizedBox(width: 8),
        Text(
          optional!,
          style: const TextStyle(
            color: MedBuddyColors.textLight,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

class MedicationEntryNameField extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final String title;
  final String hint;
  final String? Function(String?) validator;
  final bool showCounter;

  const MedicationEntryNameField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.title,
    required this.hint,
    required this.validator,
    this.showCounter = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MedicationEntrySectionTitle(title: title),
      const SizedBox(height: 10),
      TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        maxLength: 200,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          counterText: showCounter ? null : '',
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    ],
  );
}

class MedicationEntryDoseFields extends StatelessWidget {
  final String keyPrefix;
  final TextEditingController controller;
  final bool enabled;
  final String title;
  final String amountLabel;
  final String unitLabel;
  final String? unit;
  final String Function(String) unitText;
  final ValueChanged<String?> onUnitChanged;
  final String? Function(String?) validator;

  const MedicationEntryDoseFields({
    super.key,
    required this.keyPrefix,
    required this.controller,
    required this.enabled,
    required this.title,
    required this.amountLabel,
    required this.unitLabel,
    required this.unit,
    required this.unitText,
    required this.onUnitChanged,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    // 분리할 수 없는 예전 복용량은 숫자나 기본 단위로 강제 변환하지 않는다.
    final amount = TextFormField(
      key: Key('$keyPrefix-dosage'),
      controller: controller,
      enabled: enabled,
      maxLength: unit == null ? 300 : null,
      keyboardType: unit == null
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: unit == null
          ? null
          : [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(8),
            ],
      decoration: InputDecoration(
        labelText: unit == null ? null : amountLabel,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicationEntrySectionTitle(title: title),
        const SizedBox(height: 10),
        if (unit == null)
          amount
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: amount),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('$keyPrefix-unit'),
                  isExpanded: true,
                  initialValue: unit,
                  decoration: InputDecoration(
                    labelText: unitLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in medicationEntryDoseUnits)
                      DropdownMenuItem(
                        value: value,
                        child: Text(unitText(value)),
                      ),
                  ],
                  onChanged: enabled ? onUnitChanged : null,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class MedicationEntryDateButton extends StatelessWidget {
  final Key? buttonKey;
  final String label;
  final String value;
  final VoidCallback? onPressed;

  const MedicationEntryDateButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: buttonKey,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      foregroundColor: MedBuddyColors.textStrong,
      side: const BorderSide(color: MedBuddyColors.outline, width: 1.5),
    ),
    child: Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class MedicationEntryPeriodFields extends StatelessWidget {
  final String title;
  final Widget startButton;
  final Widget endButton;
  final String summary;

  const MedicationEntryPeriodFields({
    super.key,
    required this.title,
    required this.startButton,
    required this.endButton,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MedicationEntrySectionTitle(title: title),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 340 &&
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [startButton, const SizedBox(height: 8), endButton],
            );
          }
          return Row(
            children: [
              Expanded(child: startButton),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(child: endButton),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      Text(
        summary,
        style: const TextStyle(
          color: MedBuddyColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class MedicationEntryCycleChoices extends StatelessWidget {
  final String keyPrefix;
  final String value;
  final String Function(String) label;
  final ValueChanged<String>? onChanged;

  const MedicationEntryCycleChoices({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final choice in {...doseDayChoices, value})
        ChoiceChip(
          key: Key('$keyPrefix-$choice'),
          label: Text(label(choice)),
          selected: value == choice,
          onSelected: onChanged == null ? null : (_) => onChanged!(choice),
        ),
    ],
  );
}

class MedicationEntrySlotChoices extends StatelessWidget {
  final String keyPrefix;
  final Set<String> values;
  final String Function(String) label;
  final void Function(String, bool)? onChanged;

  const MedicationEntrySlotChoices({
    super.key,
    required this.keyPrefix,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final slot in medicationScheduleSlotKeys)
        FilterChip(
          key: Key('$keyPrefix-$slot'),
          label: Text(label(slot)),
          selected: values.contains(slot),
          onSelected: onChanged == null
              ? null
              : (selected) => onChanged!(slot, selected),
        ),
    ],
  );
}
