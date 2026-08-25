import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: medication_capture_options_ui_boundary.dart
// 역할: 약 정보 입력 진입점에서 공통으로 사용하는 작업 및 이미지 출처 선택 화면을 제공한다.

// 열거형명: MedicationCaptureTask
// 역할: 사용자가 선택한 약 정보 분석 작업을 구분한다.
enum MedicationCaptureTask { prescription, pill, manual }

// 열거형명: PrescriptionImageSource
// 역할: 처방전 분석에 사용할 이미지 출처를 구분한다.
enum PrescriptionImageSource { camera, gallery }

// 함수이름: showMedicationCaptureTaskOptions
// 함수역할:
// - 처방전 분석, 낱알약 식별, 직접 등록 중 수행할 작업을 선택하는 공통 하단 시트를 표시한다.
// 매개변수:
// - context: 하단 시트를 표시할 화면의 BuildContext
// - userSetting: 언어와 글자 크기 설정
// 반환값:
// - 사용자가 선택한 작업을 반환하고 시트를 닫으면 null을 반환한다.
Future<MedicationCaptureTask?> showMedicationCaptureTaskOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) {
  final text = _MedicationCaptureText(
    userSetting.language,
    multiPillIdentificationEnabled:
        userSetting.multiPillIdentificationLabEnabled,
  );

  return showModalBottomSheet<MedicationCaptureTask>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return _MedicationCaptureOptionSheet(
        children: [
          _MedicationCaptureOption(
            icon: Icons.photo_camera_outlined,
            title: text.prescriptionTask,
            subtitle: text.prescriptionTaskSubtitle,
            userSetting: userSetting,
            onTap: () {
              Navigator.pop(sheetContext, MedicationCaptureTask.prescription);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.medication_outlined,
            title: text.pillTask,
            subtitle: text.pillTaskSubtitle,
            userSetting: userSetting,
            onTap: () {
              Navigator.pop(sheetContext, MedicationCaptureTask.pill);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.edit_note_rounded,
            title: text.manualTask,
            subtitle: text.manualTaskSubtitle,
            userSetting: userSetting,
            onTap: () {
              Navigator.pop(sheetContext, MedicationCaptureTask.manual);
            },
          ),
        ],
      );
    },
  );
}

// 함수이름: showPrescriptionImageSourceOptions
// 함수역할:
// - 처방전 분석에 사용할 카메라 또는 갤러리 이미지 출처를 선택하게 한다.
// 매개변수:
// - context: 하단 시트를 표시할 화면의 BuildContext
// - userSetting: 언어와 글자 크기 설정
// 반환값:
// - 사용자가 선택한 이미지 출처를 반환하고 시트를 닫으면 null을 반환한다.
Future<PrescriptionImageSource?> showPrescriptionImageSourceOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) {
  final text = _MedicationCaptureText(
    userSetting.language,
    multiPillIdentificationEnabled:
        userSetting.multiPillIdentificationLabEnabled,
  );

  return showModalBottomSheet<PrescriptionImageSource>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return _MedicationCaptureOptionSheet(
        children: [
          _MedicationCaptureOption(
            icon: Icons.photo_camera_outlined,
            title: text.cameraOption,
            subtitle: text.cameraOptionSubtitle,
            userSetting: userSetting,
            onTap: () {
              Navigator.pop(sheetContext, PrescriptionImageSource.camera);
            },
          ),
          const SizedBox(height: 10),
          _MedicationCaptureOption(
            icon: Icons.photo_library_outlined,
            title: text.galleryOption,
            subtitle: text.galleryOptionSubtitle,
            userSetting: userSetting,
            onTap: () {
              Navigator.pop(sheetContext, PrescriptionImageSource.gallery);
            },
          ),
        ],
      );
    },
  );
}

// 클래스명: _MedicationCaptureOptionSheet
// 역할: 약 정보 입력 선택지를 작은 화면에서도 스크롤 가능한 하단 시트로 배치한다.
// 주요 책임:
// - 공통 상단 핸들과 선택지 여백을 제공한다.
// - 큰 글자 설정에서도 선택지가 화면 아래로 넘치지 않게 한다.
class _MedicationCaptureOptionSheet extends StatelessWidget {
  final List<Widget> children;

  const _MedicationCaptureOptionSheet({required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: MedBuddyColors.outline,
                borderRadius: MedBuddyRadii.pill,
              ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

// 클래스명: _MedicationCaptureOption
// 역할: 약 정보 분석 작업 또는 이미지 출처 선택지를 한 행으로 표시한다.
// 주요 책임:
// - 아이콘, 제목, 설명을 사용자 글자 크기에 맞춰 표시한다.
// - 선택 시 호출자가 전달한 동작을 실행한다.
class _MedicationCaptureOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final UserSetting userSetting;
  final VoidCallback onTap;

  const _MedicationCaptureOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Material(
      color: const Color(0xFFF4FFF4),
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13 * scale,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _MedicationCaptureText
// 역할: 공통 약 정보 입력 선택 화면의 한국어와 영어 문구를 제공한다.
class _MedicationCaptureText {
  final String language;
  final bool multiPillIdentificationEnabled;

  const _MedicationCaptureText(
    this.language, {
    required this.multiPillIdentificationEnabled,
  });

  bool get isEnglish => language == 'en';

  String get prescriptionTask =>
      isEnglish ? 'Analyze a prescription' : '처방전 분석';
  String get prescriptionTaskSubtitle => isEnglish
      ? 'Extract medication names and schedules.'
      : '처방전에서 약 이름과 복약 일정을 확인합니다.';
  String get pillTask => isEnglish ? 'Identify a loose pill' : '낱알약 식별';
  String get pillTaskSubtitle {
    if (multiPillIdentificationEnabled) {
      return isEnglish
          ? 'Identify one pill or add separate photos for a Labs batch review.'
          : '한 알을 식별하거나 알약별 사진을 추가해 실험실 일괄 검토를 합니다.';
    }
    return isEnglish
        ? 'Compare a photographed pill with MFDS candidates.'
        : '촬영한 알약 한 개를 식약처 제품 후보와 비교합니다.';
  }

  String get manualTask => isEnglish ? 'Add manually' : '직접 등록';
  String get manualTaskSubtitle => isEnglish
      ? 'Enter a medication name and schedule without a photo.'
      : '사진이 없어도 약 이름과 복용 일정을 직접 입력합니다.';
  String get cameraOption => isEnglish ? 'Take Photo' : '카메라로 촬영';
  String get cameraOptionSubtitle =>
      isEnglish ? 'Take a prescription photo now.' : '처방전을 바로 촬영합니다.';
  String get galleryOption => isEnglish ? 'Choose From Gallery' : '갤러리에서 선택';
  String get galleryOptionSubtitle =>
      isEnglish ? 'Load a saved prescription image.' : '저장된 처방전 이미지를 불러옵니다.';
}
