// 파일명: home_linked_patient_hint.dart
// 역할: 보호자 계정 홈의 "연동된 환자 일정 보기" 안내를 테두리 없이 글자 높이에 맞춘 행으로 그린다.
import 'package:flutter/material.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: HomeLinkedPatientHint
// 역할: 홈 일정을 연동된 환자 기준으로 바꾸는 설정으로 안내한다. 홈이 스크롤 없이 한 화면에
//   들어가도록 배경·테두리 없이 제목과 짧은 설명 두 줄 높이만 차지하고, 누르는 영역은 48dp를
//   유지한다. 큰 글씨에서는 줄바꿈으로 높이를 늘린다.
class HomeLinkedPatientHint extends StatelessWidget {
  final bool isEnglish;
  final VoidCallback onTap;

  // 함수이름: HomeLinkedPatientHint
  // 함수역할: 안내 문구 언어와 눌렀을 때 열 화면 동작을 받는다.
  // 매개변수: isEnglish: 영어 문구 여부, onTap: 설정 화면을 여는 동작. 반환값: 없음.
  const HomeLinkedPatientHint({
    super.key,
    required this.isEnglish,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 아이콘·제목·설명·화살표를 한 행에 놓은 48dp 이상의 누를 수 있는 행을 만든다.
  // 매개변수: context: 위젯 트리 위치. 반환값: 안내 행 위젯.
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('caregiver-home-source-hint'),
        borderRadius: MedBuddyRadii.control,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
          child: Row(
            children: [
              const Icon(
                Icons.people_outline,
                color: MedBuddyColors.primaryDark,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEnglish
                          ? 'View linked patient schedules'
                          : '연동된 환자 일정 보기',
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnglish
                          ? 'Switch Home to “Linked patients”.'
                          : '홈 일정을 ‘연동된 환자’로 바꿔요.',
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
