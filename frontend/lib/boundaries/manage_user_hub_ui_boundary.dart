import 'package:flutter/material.dart';

import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: manage_user_hub_ui_boundary.dart
// 역할: 계정 요약과 환자·보호자 연동, 환경설정 진입점을 한 화면에 구성한다.

// 클래스명: ManageUserHubUI
// 역할: 하단 탐색의 내 정보 목적지에서 계정 및 연결 관리 기능을 제공한다.
// 주요 책임:
// - 현재 인증 세션을 개인정보를 과도하게 노출하지 않는 요약으로 표시한다.
// - 환자·보호자 연동 화면과 기존 환경설정 화면으로 이동할 수 있게 한다.
class ManageUserHubUI extends StatelessWidget {
  final UserSetting userSetting;
  final AuthenticationControl authenticationControl;
  final VoidCallback onPatientCaregiverLinkRequested;
  final VoidCallback onUserSettingRequested;

  const ManageUserHubUI({
    super.key,
    required this.userSetting,
    required this.authenticationControl,
    required this.onPatientCaregiverLinkRequested,
    required this.onUserSettingRequested,
  });

  @override
  Widget build(BuildContext context) {
    final text = _UserHubText(userSetting.language);
    final email = (authenticationControl.session?.email ?? '').trim();
    final accountLabel = authenticationControl.isAnonymous
        ? text.guestAccount
        : email.isEmpty
        ? text.signedInAccount
        : email;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MedBuddySpacing.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                Text(
                  text.title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text.subtitle,
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                _AccountSummaryCard(
                  accountLabel: accountLabel,
                  accountType: authenticationControl.isAnonymous
                      ? text.guestDescription
                      : text.signedInDescription,
                ),
                const SizedBox(height: 16),
                _UserHubActionCard(
                  key: const ValueKey('userHubCaregiverLinkAction'),
                  icon: Icons.people_alt_outlined,
                  title: text.patientCaregiver,
                  subtitle: text.patientCaregiverDescription,
                  backgroundColor: MedBuddyColors.mint,
                  iconColor: MedBuddyColors.primaryDark,
                  onTap: onPatientCaregiverLinkRequested,
                ),
                const SizedBox(height: 12),
                _UserHubActionCard(
                  key: const ValueKey('userHubSettingsAction'),
                  icon: Icons.settings_outlined,
                  title: text.settings,
                  subtitle: text.settingsDescription,
                  backgroundColor: MedBuddyColors.surface,
                  iconColor: MedBuddyColors.textStrong,
                  onTap: onUserSettingRequested,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  final String accountLabel;
  final String accountType;

  const _AccountSummaryCard({
    required this.accountLabel,
    required this.accountType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MedBuddyColors.primary,
        borderRadius: MedBuddyRadii.largeCard,
        boxShadow: MedBuddyShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accountLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  accountType,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserHubActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _UserHubActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: MedBuddyRadii.largeCard,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            border: Border.all(color: MedBuddyColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: MedBuddyColors.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: MedBuddyColors.textSubtle,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserHubText {
  final String language;

  const _UserHubText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get title => isEnglish ? 'My Info' : '내 정보';
  String get subtitle => isEnglish
      ? 'Manage your account, connections, and accessibility preferences.'
      : '계정과 연동 상태, 접근성 환경설정을 관리하세요.';
  String get guestAccount => isEnglish ? 'Guest account' : '게스트 계정';
  String get signedInAccount => isEnglish ? 'Signed-in account' : '로그인 계정';
  String get guestDescription => isEnglish
      ? 'Guest data cannot be restored after account deletion.'
      : '게스트 데이터는 계정 삭제 후 복구할 수 없습니다.';
  String get signedInDescription => isEnglish
      ? 'Your medication data is scoped to this authenticated account.'
      : '복약 정보는 현재 로그인 계정에 안전하게 연결됩니다.';
  String get patientCaregiver =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  String get patientCaregiverDescription => isEnglish
      ? 'Connect schedules and review linked patient medication.'
      : '복약 일정을 연결하고 연동된 환자의 복약 상태를 확인하세요.';
  String get settings => isEnglish ? 'Settings' : '환경설정';
  String get settingsDescription => isEnglish
      ? 'Adjust text size, voice speed, language, and account settings.'
      : '글자 크기, 읽기 속도, 언어 및 계정 설정을 조정하세요.';
}
