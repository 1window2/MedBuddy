// 파일명: medbuddy_select_all_bar.dart
// 역할: 알림함과 채팅 첨부용 약 선택 화면이 함께 쓰는 전체·일부·미선택 체크박스 줄을 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// Class Name: MedBuddySelectAllBar
// Role: Display select-all state and the current selection count.
// Responsibilities: Represent none/all/partial selection and delegate toggling to the owner.
// Attributes: tileKey/countKey (Key): stable child identities; label/countLabel (String): display text; selectedCount/totalCount (int): selection state; onToggleAll (VoidCallback?): action or disabled state.
class MedBuddySelectAllBar extends StatelessWidget {
  final Key tileKey;
  final String label;
  final String countLabel;
  final Key countKey;
  final int selectedCount;
  final int totalCount;
  final VoidCallback? onToggleAll;

  // Function Name: MedBuddySelectAllBar
  // Description: Configure the select-all control without owning selection state.
  // Parameters: key (Key?): widget identity; tileKey/countKey (Key): child IDs; label/countLabel (String): display text; selectedCount/totalCount (int): counts; onToggleAll (VoidCallback?): toggle callback.
  // Returns: MedBuddySelectAllBar: configured selection bar.
  const MedBuddySelectAllBar({
    super.key,
    required this.tileKey,
    required this.label,
    required this.countLabel,
    required this.countKey,
    required this.selectedCount,
    required this.totalCount,
    required this.onToggleAll,
  });

  // Function Name: build
  // Description: Derive tri-state checkbox state from selected and total counts and display a wrapping count label.
  // Parameters: context (BuildContext): widget build context.
  // Returns: Widget: selection bar, disabled when onToggleAll is null.
  @override
  Widget build(BuildContext context) => Material(
    color: MedBuddyColors.surfaceSubtle,
    shape: const Border(bottom: BorderSide(color: MedBuddyColors.divider)),
    child: CheckboxListTile(
      key: tileKey,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MedBuddySpacing.pageHorizontal,
        vertical: 8,
      ),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: MedBuddyColors.primary,
      checkColor: MedBuddyColors.surface,
      checkboxShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      tristate: true,
      value: selectedCount == 0
          ? false
          : selectedCount == totalCount
          ? true
          : null,
      onChanged: onToggleAll == null ? null : (_) => onToggleAll!(),
      title: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          KeepWordsText(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: 0,
              color: MedBuddyColors.textStrong,
            ),
          ),
          KeepWordsText(
            countLabel,
            key: countKey,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: 0,
              color: selectedCount == 0
                  ? MedBuddyColors.textMuted
                  : MedBuddyColors.primaryDark,
            ),
          ),
        ],
      ),
    ),
  );
}
