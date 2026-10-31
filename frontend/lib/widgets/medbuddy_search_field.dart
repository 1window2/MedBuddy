// 기능·진료과 검색의 입력창과 결과 테두리를 같은 형태로 유지한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

class MedBuddySearchField extends StatelessWidget {
  const MedBuddySearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.isEnglish,
    this.inputKey,
    this.clearKey,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onChanged;
  final bool isEnglish;
  final Key? inputKey;
  final Key? clearKey;

  @override
  Widget build(BuildContext context) => TextField(
    key: inputKey,
    controller: controller,
    maxLength: 120,
    style: MedBuddyTextStyles.menuBody,
    textInputAction: TextInputAction.search,
    onChanged: (_) => onChanged(),
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isNotEmpty
          ? IconButton(
              key: clearKey,
              tooltip: isEnglish ? 'Clear search' : '검색어 지우기',
              onPressed: () {
                controller.clear();
                onChanged();
              },
              icon: const Icon(Icons.close),
            )
          : null,
    ),
  );
}

class MedBuddySearchPanel extends StatelessWidget {
  const MedBuddySearchPanel({super.key, required this.child});

  final Widget child;

  // 안의 목록 터치 효과가 보이도록 장식 상자가 아닌 Material로 그린다.
  @override
  Widget build(BuildContext context) => Material(
    color: MedBuddyColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: MedBuddyRadii.card,
      side: const BorderSide(color: MedBuddyColors.outline),
    ),
    child: child,
  );
}
