import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: input_prescription_ui_boundary.dart
// 역할: MedBuddy 홈 화면과 처방전 입력 진입점을 구성한다.

// 클래스명: InputPrescriptionUI
// 역할: 오늘의 복약 일정, 처방전 촬영, 저장된 복약 정보, 환자/보호자 연동으로 이동하는 홈 화면이다.
// 주요 책임:
// - 사용자 설정에 맞춘 홈 화면 문구와 글자 크기를 보여준다.
// - 카메라/갤러리 처방전 입력 방식을 선택할 수 있게 한다.
// - OCR 진행 중에는 입력 화면 대신 진행 상태를 보여준다.
class InputPrescriptionUI extends StatelessWidget {
  final String statusMessage;
  final UserSetting userSetting;
  final VoidCallback? onPrescriptionScanRequested;
  final VoidCallback? onPrescriptionGalleryRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onPatientCaregiverLinkRequested;
  final VoidCallback? onUserSettingRequested;
  final bool isAnalyzing;

  const InputPrescriptionUI({
    super.key,
    required this.statusMessage,
    required this.userSetting,
    required this.onPrescriptionScanRequested,
    required this.onPrescriptionGalleryRequested,
    required this.onTodayScheduleRequested,
    required this.onSavedMedicationRequested,
    required this.onPatientCaregiverLinkRequested,
    required this.onUserSettingRequested,
  }) : isAnalyzing = false;

  const InputPrescriptionUI.analyzing({
    super.key,
    required this.statusMessage,
  })  : userSetting = const UserSetting(),
        onPrescriptionScanRequested = null,
        onPrescriptionGalleryRequested = null,
        onTodayScheduleRequested = null,
        onSavedMedicationRequested = null,
        onPatientCaregiverLinkRequested = null,
        onUserSettingRequested = null,
        isAnalyzing = true;

  @override
  Widget build(BuildContext context) {
    final text = _HomeText(userSetting.language);

    if (isAnalyzing) {
      return _buildAnalyzingScreen(text);
    }

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _HomeHeader(
              onSettingPressed: onUserSettingRequested,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(42, 10, 42, 32),
                child: Column(
                  children: [
                    _ScheduleCard(
                      text: text,
                      userSetting: userSetting,
                      onTap: onTodayScheduleRequested,
                    ),
                    const SizedBox(height: 20),
                    _HomeActionCard(
                      icon: Icons.photo_camera_outlined,
                      title: text.scanPrescription,
                      subtitle: text.scanPrescriptionSubtitle,
                      filled: true,
                      userSetting: userSetting,
                      onTap: () => _showPrescriptionInputOptions(context, text),
                    ),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      icon: Icons.medication_outlined,
                      title: text.savedMedication,
                      subtitle: text.savedMedicationSubtitle,
                      filled: false,
                      userSetting: userSetting,
                      onTap: onSavedMedicationRequested,
                    ),
                    const SizedBox(height: 22),
                    _LinkCard(
                      title: text.patientCaregiverLink,
                      userSetting: userSetting,
                      onTap: onPatientCaregiverLinkRequested,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void clickPrescriptionInput() {
    onPrescriptionScanRequested?.call();
  }

  void clickPrescriptionImageSelect() {
    onPrescriptionGalleryRequested?.call();
  }

  String showMaskedInfrmation() {
    return statusMessage;
  }

  // 함수명: _showPrescriptionInputOptions
  // 함수역할:
  // - 처방전 입력 버튼을 눌렀을 때 카메라와 갤러리 선택지를 하단 시트로 보여준다.
  // 매개변수:
  // - context: 하단 시트를 띄울 BuildContext
  // - text: 현재 언어에 맞는 홈 화면 문구 묶음
  // 반환값:
  // - 없음
  void _showPrescriptionInputOptions(
    BuildContext context,
    _HomeText text,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DC),
                    borderRadius: MedBuddyRadii.pill,
                  ),
                ),
                const SizedBox(height: 18),
                _PrescriptionInputOption(
                  icon: Icons.photo_camera_outlined,
                  title: text.cameraOption,
                  subtitle: text.cameraOptionSubtitle,
                  userSetting: userSetting,
                  onTap: () {
                    Navigator.pop(context);
                    onPrescriptionScanRequested?.call();
                  },
                ),
                const SizedBox(height: 10),
                _PrescriptionInputOption(
                  icon: Icons.photo_library_outlined,
                  title: text.galleryOption,
                  subtitle: text.galleryOptionSubtitle,
                  userSetting: userSetting,
                  onTap: () {
                    Navigator.pop(context);
                    onPrescriptionGalleryRequested?.call();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 함수명: _buildAnalyzingScreen
  // 함수역할:
  // - 처방전 이미지가 선택된 뒤 OCR 요청이 진행되는 동안 보여줄 화면을 만든다.
  // 매개변수:
  // - text: 현재 언어에 맞는 홈 화면 문구 묶음
  // 반환값:
  // - 분석 진행 상태 Widget
  Widget _buildAnalyzingScreen(_HomeText text) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFECFDF5), Colors.white],
          ),
        ),
        child: Center(
          child: Container(
            width: 328,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD1D5DC), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 22,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    color: MedBuddyColors.primary,
                    strokeWidth: 7,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  text.analyzingTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6A7282),
                    fontSize: 15,
                    height: 1.45,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 26),
                ClipRRect(
                  borderRadius: MedBuddyRadii.pill,
                  child: const LinearProgressIndicator(
                    minHeight: 10,
                    color: MedBuddyColors.primary,
                    backgroundColor: Color(0xFFE5E7EB),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback? onSettingPressed;

  const _HomeHeader({
    required this.onSettingPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      width: double.infinity,
      color: MedBuddyColors.primary,
      padding: const EdgeInsets.fromLTRB(48, 44, 34, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEDbuddy',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '건강한 복약 관리 도우미',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Material(
            color: MedBuddyColors.primaryDark,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onSettingPressed,
              child: const SizedBox(
                width: 55,
                height: 55,
                child: Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 29,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final _HomeText text;
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _ScheduleCard({
    required this.text,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return _SurfaceCard(
      minHeight: 171,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: MedBuddyColors.primary,
            size: 50,
          ),
          const SizedBox(height: 12),
          Text(
            text.todaySchedule,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF0A0A0A),
              fontSize: 22 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            text.noMedication,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textLight,
              fontSize: 14 * scale,
              height: 1.25,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? MedBuddyColors.primary : Colors.white;
    final foreground = filled ? Colors.white : MedBuddyColors.primaryDark;
    final secondary = filled ? MedBuddyColors.mint : MedBuddyColors.primary;
    final scale = userSetting.contentTextScale;

    return Material(
      color: background,
      borderRadius: MedBuddyRadii.card,
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: filled ? 176 : 182),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: filled
                ? null
                : Border.all(color: MedBuddyColors.mint, width: 2.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 43),
              const SizedBox(height: 15),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 23 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondary,
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final String title;
  final UserSetting userSetting;
  final VoidCallback? onTap;

  const _LinkCard({
    required this.title,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return _SurfaceCard(
      minHeight: 92,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Center(
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MedBuddyColors.primaryDark,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _SurfaceCard({
    required this.child,
    required this.minHeight,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: MedBuddyRadii.card,
      elevation: 7,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.16),
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 2.7),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PrescriptionInputOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final UserSetting userSetting;
  final VoidCallback onTap;

  const _PrescriptionInputOption({
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
              Icon(
                icon,
                color: MedBuddyColors.primary,
                size: 30,
              ),
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

class _HomeText {
  final String language;

  const _HomeText(this.language);

  bool get isEnglish => language == 'en';

  String get todaySchedule => isEnglish ? 'Today\'s Medication' : '오늘의 복약 일정';
  String get noMedication => isEnglish
      ? 'No medicine registered\nScan a prescription'
      : '등록된 약이 없습니다\n처방전을 촬영해주세요';
  String get scanPrescription => isEnglish ? 'Scan Prescription' : '처방전 촬영하기';
  String get scanPrescriptionSubtitle =>
      isEnglish ? 'Take a photo of your prescription' : '카메라로 처방전을 찍어주세요';
  String get savedMedication => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  String get savedMedicationSubtitle =>
      isEnglish ? 'Check saved medication info' : '저장된 복약 정보 확인';
  String get patientCaregiverLink =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  String get cameraOption => isEnglish ? 'Take Photo' : '카메라로 촬영';
  String get cameraOptionSubtitle =>
      isEnglish ? 'Take a prescription photo now.' : '처방전을 바로 촬영합니다.';
  String get galleryOption => isEnglish ? 'Choose From Gallery' : '갤러리에서 선택';
  String get galleryOptionSubtitle =>
      isEnglish ? 'Load a saved prescription image.' : '저장된 처방전 이미지를 불러옵니다.';
  String get analyzingTitle =>
      isEnglish ? 'Analyzing prescription...' : '처방전 인식 중...';
}
