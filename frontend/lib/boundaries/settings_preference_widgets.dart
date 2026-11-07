part of 'manage_user_setting_ui_boundary.dart';

// 파일명: settings_preference_widgets.dart
// 역할: 복약·알림 및 화면·음성 설정에서 같은 구역 제목과 목록 행을 공유한다.

// Class Name: _SettingsSection
// Role: A settings section with a heading, optional explanation and shared-width preference rows.
// Responsibilities: Marks the heading for accessibility and separates adjacent rows without a trailing divider.
// Attributes: title (String): heading; description (String?): explanation; children (List<Widget>): preference rows.
class _SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  // 함수이름: _SettingsSection
  // 함수역할: 구역 제목과 설정 행을 저장하고 설명은 선택적으로 받는다.
  // 매개변수: key (Key?): 식별 키; title (String): 제목; children (List<Widget>): 행; description (String?): 설명.
  // 반환값: 새 _SettingsSection.
  const _SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  // Function Name: build
  // Description: Displays the title and optional explanation above rows separated only between adjacent children.
  // Parameters: context (BuildContext): Theme and text-scaling location.
  // Returns: Settings-section Container.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    decoration: BoxDecoration(
      color: MedBuddyColors.surface,
      border: Border.all(color: MedBuddyColors.cardBorder),
      borderRadius: MedBuddyRadii.card,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              color: MedBuddyColors.primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          KeepWordsText(
            description!,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 4),
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(height: 1, color: MedBuddyColors.divider),
        ],
      ],
    ),
  );
}
