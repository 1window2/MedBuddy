// 파일명: medication_photo_source_sheet.dart
// 역할: 약 사진용 카메라·갤러리 출처를 선택하는 공통 하단 메뉴.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_choice_sheet.dart';

// 함수이름: showMedicationPhotoSourceOptions
// 함수역할: 카메라와 갤러리를 큰 타일 두 개로 보이고 출처를 하나 선택받는다.
// 매개변수:
// - context (BuildContext): 시트를 열 위치.
// - language (String): 표시 언어 코드.
// 반환값: 선택한 ImageSource. 닫으면 null.
Future<ImageSource?> showMedicationPhotoSourceOptions({
  required BuildContext context,
  required String language,
}) {
  final isEnglish = isEnglishLanguage(language);
  return showMedBuddyChoiceSheet<ImageSource>(
    context: context,
    title: isEnglish ? 'Add a photo' : '사진을 어떻게 가져올까요?',
    choices: [
      MedBuddyChoice(
        value: ImageSource.camera,
        icon: Icons.photo_camera_outlined,
        label: isEnglish ? 'Take photo' : '카메라로 촬영',
        tileKey: const ValueKey('photoSourceCamera'),
      ),
      MedBuddyChoice(
        value: ImageSource.gallery,
        icon: Icons.photo_library_outlined,
        label: isEnglish ? 'From gallery' : '갤러리에서 선택',
        tileKey: const ValueKey('photoSourceGallery'),
      ),
    ],
  );
}
