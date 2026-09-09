import 'package:flutter/material.dart';

import '../controls/authentication_control.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// File Name: manage_user_hub_ui_boundary.dart
// Role: UI boundaries and helpers for account summaries and access to link management and settings.

// Class Name: ManageUserHubUI
// Role: Represents the account summary and link or settings management actions.
// Responsibilities:
// - Summarizes the authenticated session without unnecessarily exposing personal information.
// - Connects patient-caregiver linking and settings navigation.
// Attributes:
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - authenticationControl (AuthenticationControl): Provider of authentication, account, and multi-factor state and actions.
// - onPatientCaregiverLinkRequested (VoidCallback): Callback opening patient-caregiver link management.
// - onUserSettingRequested (VoidCallback): Callback opening user settings.
class ManageUserHubUI extends StatelessWidget {
  final UserSetting userSetting;
  final AuthenticationControl authenticationControl;
  final VoidCallback onPatientCaregiverLinkRequested;
  final VoidCallback onUserSettingRequested;

  // Function Name: ManageUserHubUI
  // Description: Initializes the account summary and link or settings management actions with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // - authenticationControl (AuthenticationControl): Provider of authentication, account, and multi-factor state and actions.
  // - onPatientCaregiverLinkRequested (VoidCallback): Callback opening patient-caregiver link management.
  // - onUserSettingRequested (VoidCallback): Callback opening user settings.
  // Returns: Initialized ManageUserHubUI instance.
  const ManageUserHubUI({
    super.key,
    required this.userSetting,
    required this.authenticationControl,
    required this.onPatientCaregiverLinkRequested,
    required this.onUserSettingRequested,
  });

  // Function Name: build
  // Description: Renders the account summary and link or settings management actions from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the account summary and link or settings management actions.
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

// Class Name: _AccountSummaryCard
// Role: Represents a sign-in summary with limited personal information exposure.
// Responsibilities:
// - Composes a sign-in summary with limited personal information exposure using the display values and actions supplied by its parent.
// Attributes:
// - accountLabel (String): Label identifying the signed-in account type.
// - accountType (String): Label identifying the signed-in account type.
class _AccountSummaryCard extends StatelessWidget {
  final String accountLabel;
  final String accountType;

  // Function Name: _AccountSummaryCard
  // Description: Initializes a sign-in summary with limited personal information exposure with the supplied configuration.
  // Parameters:
  // - accountLabel (String): Label identifying the signed-in account type.
  // - accountType (String): Label identifying the signed-in account type.
  // Returns: Initialized _AccountSummaryCard instance.
  const _AccountSummaryCard({
    required this.accountLabel,
    required this.accountType,
  });

  // Function Name: build
  // Description: Renders a sign-in summary with limited personal information exposure from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a sign-in summary with limited personal information exposure.
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

// Class Name: _UserHubActionCard
// Role: Represents a link-management or settings action in My Info.
// Responsibilities:
// - Composes a link-management or settings action in My Info using the display values and actions supplied by its parent.
// Attributes:
// - icon (IconData): Icon shown in normal or selected state.
// - title (String): Heading shown for the screen, section, or item.
// - subtitle (String): Supporting explanation or account detail below the primary label.
// - backgroundColor (Color): Background color for the item.
class _UserHubActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  // Function Name: _UserHubActionCard
  // Description: Initializes a link-management or settings action in My Info with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - icon (IconData): Icon shown in normal or selected state.
  // - title (String): Heading shown for the screen, section, or item.
  // - subtitle (String): Supporting explanation or account detail below the primary label.
  // - backgroundColor (Color): Background color for the item.
  // - iconColor (Color): Foreground or accent color applied to text, icons, or state guidance.
  // - onTap (VoidCallback): Callback executing the item's documented primary action.
  // Returns: Initialized _UserHubActionCard instance.
  const _UserHubActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  // Function Name: build
  // Description: Renders a link-management or settings action in My Info from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a link-management or settings action in My Info.
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

// Class Name: _UserHubText
// Role: Represents localized wording for account summaries and access to link management and settings.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for account summaries and access to link management and settings.
// Attributes:
// - language (String): Language code selecting visible wording.
class _UserHubText {
  final String language;

  // Function Name: _UserHubText
  // Description: Stores the language used to select localized wording for account summaries and access to link management and settings.
  // Parameters:
  // - language (String): Language code selecting visible wording.
  // Returns: Initialized _UserHubText instance.
  const _UserHubText(this.language);

  // Function Name: isEnglish
  // Description: Recognizes English locale prefixes after trimming and lowercasing the language code.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  // Function Name: title
  // Description: Provides localized wording for "My Info" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get title => isEnglish ? 'My Info' : '내 정보';
  // Function Name: subtitle
  // Description: Provides localized wording for "Manage your account, connections, and accessibility preferences." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get subtitle => isEnglish
      ? 'Manage your account, connections, and accessibility preferences.'
      : '계정과 연동 상태, 접근성 환경설정을 관리하세요.';
  // Function Name: guestAccount
  // Description: Provides localized wording for "Guest account" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestAccount => isEnglish ? 'Guest account' : '게스트 계정';
  // Function Name: signedInAccount
  // Description: Provides localized wording for "Signed-in account" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get signedInAccount => isEnglish ? 'Signed-in account' : '로그인 계정';
  // Function Name: guestDescription
  // Description: Provides localized wording for "Guest data cannot be restored after account deletion." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get guestDescription => isEnglish
      ? 'Guest data cannot be restored after account deletion.'
      : '게스트 데이터는 계정 삭제 후 복구할 수 없습니다.';
  // Function Name: signedInDescription
  // Description: Provides localized wording for "Your medication data is scoped to this authenticated account." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get signedInDescription => isEnglish
      ? 'Your medication data is scoped to this authenticated account.'
      : '복약 정보는 현재 로그인 계정에 안전하게 연결됩니다.';
  // Function Name: patientCaregiver
  // Description: Provides localized wording for "Patient/Caregiver Link" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get patientCaregiver =>
      isEnglish ? 'Patient/Caregiver Link' : '환자/보호자 연동';
  // Function Name: patientCaregiverDescription
  // Description: Provides localized wording for "Connect schedules and review linked patient medication." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get patientCaregiverDescription => isEnglish
      ? 'Connect schedules and review linked patient medication.'
      : '복약 일정을 연결하고 연동된 환자의 복약 상태를 확인하세요.';
  // Function Name: settings
  // Description: Provides localized wording for "Settings" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get settings => isEnglish ? 'Settings' : '환경설정';
  // Function Name: settingsDescription
  // Description: Provides localized wording for "Adjust text size, voice speed, language, and account settings." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get settingsDescription => isEnglish
      ? 'Adjust text size, voice speed, language, and account settings.'
      : '글자 크기, 읽기 속도, 언어 및 계정 설정을 조정하세요.';
}
