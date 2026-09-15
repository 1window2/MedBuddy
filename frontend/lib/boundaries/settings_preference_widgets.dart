part of 'manage_user_setting_ui_boundary.dart';

// 파일명: settings_preference_widgets.dart
// 역할: 복약·알림 및 화면·음성 설정에서 같은 구역 제목과 목록 행을 공유한다.

// 클래스명: _SettingsSection
// 역할: 구역 제목과 필요한 설명, 구분선이 있는 설정 목록을 제공한다.
class _SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  // 함수이름: _SettingsSection
  // 함수역할: 제목·설명·설정 행을 받는다. 반환값: 설정 구역 위젯.
  const _SettingsSection({
    required this.title,
    required this.children,
    this.description,
  });

  // 함수이름: build
  // 함수역할: context의 글씨 배율로 구역을 표시한다. 반환값: 너비를 공유하는 설정 목록.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(
            color: MedBuddyColors.primaryDark,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: 6),
        Text(
          description!,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
      const SizedBox(height: 8),
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index < children.length - 1)
          const Divider(height: 1, color: MedBuddyColors.divider),
      ],
    ],
  );
}
