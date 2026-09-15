import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/medbuddy_theme.dart';

// context와 language로 공통 사진 출처 메뉴를 열어 선택한 출처를 반환한다. 취소하면 null이다.
Future<ImageSource?> showMedicationPhotoSourceOptions({
  required BuildContext context,
  required String language,
}) {
  final isEnglish = language == 'en';
  return showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MedBuddyColors.surface,
    showDragHandle: true,
    // 큰 글씨나 가로 화면에서도 두 선택지 모두 스크롤로 접근할 수 있다.
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PhotoSourceRow(
              icon: Icons.photo_camera_outlined,
              label: isEnglish ? 'Take Photo' : '카메라로 촬영',
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            const Divider(height: 1, color: MedBuddyColors.divider),
            _PhotoSourceRow(
              icon: Icons.photo_library_outlined,
              label: isEnglish ? 'Choose From Gallery' : '갤러리에서 선택',
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

// 사진 출처를 선택하는 공통 행으로, 설명 대신 아이콘과 명확한 명령을 표시한다.
class _PhotoSourceRow extends StatelessWidget {
  // icon과 label로 표시하고, 선택 시 onTap을 실행하는 행을 만든다.
  const _PhotoSourceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  // context의 글씨 배율을 반영하고 최소 56 높이의 선택 행을 반환한다.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primaryDark),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
