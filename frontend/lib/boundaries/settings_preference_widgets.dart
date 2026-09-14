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

// 클래스명: _SettingsPreferenceRow
// 역할: 시간·공개 범위·화면 이동을 같은 라벨·값·화살표 배치로 제공한다.
class _SettingsPreferenceRow extends StatelessWidget {
  final String title;
  final String? description;
  final String? value;
  final VoidCallback? onTap;

  // 함수이름: _SettingsPreferenceRow
  // 함수역할: 라벨·설명·현재 값·선택 콜백을 받는다. 반환값: 설정 행.
  const _SettingsPreferenceRow({
    required this.title,
    required this.onTap,
    this.description,
    this.value,
    super.key,
  });

  // 함수이름: build
  // 함수역할: 큰 글씨에서 현재 값의 너비를 제한해 제목과 겹치지 않게 배치한다.
  // 매개변수: context는 접근성 배율과 테마. 반환값: 최소 64 높이의 설정 행.
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: onTap == null
                                  ? MedBuddyColors.textMuted
                                  : MedBuddyColors.textStrong,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              description!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: MedBuddyColors.textMuted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.42,
                        ),
                        child: Text(
                          value!,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: MedBuddyColors.primaryDark,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: MedBuddyColors.textSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
