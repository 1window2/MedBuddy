// 파일명: medication_photo_source_sheet.dart
// 역할: 약 사진용 카메라·갤러리 출처를 선택하는 공통 하단 메뉴.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/keep_words_text.dart';

// 함수이름: showMedicationPhotoSourceOptions
// 함수역할: 카메라와 갤러리를 스크롤 가능한 메뉴로 표시하고 출처를 하나 선택받는다.
// 매개변수: context (BuildContext): 메뉴 위치; language (String): 표시 언어 코드.
// 반환값: 선택한 ImageSource; 취소하면 null인 Future.
Future<ImageSource?> showMedicationPhotoSourceOptions({
  required BuildContext context,
  required String language,
}) {
  final isEnglish = isEnglishLanguage(language);
  var responded = false;
  // 함수이름: select
  // 함수역할: 살아 있는 현재 선택창에서 최초 응답만 처리하여 아래 등록 경로의 중복 종료를 막는다.
  // 매개변수: sheetContext (BuildContext): 선택창 위치; source (ImageSource): 선택 출처.
  // 반환값: 없음. 경로 결과로 source를 반환한다.
  void select(BuildContext sheetContext, ImageSource source) {
    if (responded ||
        !sheetContext.mounted ||
        ModalRoute.of(sheetContext)?.isCurrent != true) {
      return;
    }
    responded = true;
    Navigator.pop(sheetContext, source);
  }

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
              onTap: () => select(sheetContext, ImageSource.camera),
            ),
            const Divider(height: 1, color: MedBuddyColors.divider),
            _PhotoSourceRow(
              icon: Icons.photo_library_outlined,
              label: isEnglish ? 'Choose From Gallery' : '갤러리에서 선택',
              onTap: () => select(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

// Class Name: _PhotoSourceRow
// Role: A shared camera/gallery choice row with a scalable label.
// Responsibilities: Provides a minimum tap area without constraining large-text height.
// Attributes: icon (IconData): source symbol; label (String): action label; onTap (VoidCallback): selection callback.
class _PhotoSourceRow extends StatelessWidget {
  // 함수이름: _PhotoSourceRow
  // 함수역할: 아이콘과 명령 문구를 표시하고 선택 콜백을 연결한다.
  // 매개변수: icon (IconData): 출처 아이콘; label (String): 문구; onTap (VoidCallback): 선택 처리.
  // 반환값: 새 _PhotoSourceRow.
  const _PhotoSourceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  // Function Name: build
  // Description: Builds a padded source choice with a minimum height and wrapping label.
  // Parameters: context (BuildContext): Text scaling and theme location.
  // Returns: InkWell invoking onTap when selected.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: MedBuddyRadii.small,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primaryDark),
              const SizedBox(width: 16),
              Expanded(
                child: KeepWordsText(
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
