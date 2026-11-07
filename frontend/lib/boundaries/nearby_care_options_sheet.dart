// 파일명: nearby_care_options_sheet.dart
// 역할: 주변 병원 또는 약국 검색을 선택하는 공통 메뉴.

// 홈에서 병원과 약국 중 검색할 대상을 고르는 공통 선택창.
import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_option_sheet.dart';

// 클래스명: NearbyCareDestination
// 역할: 주변 시설 검색 목적지.
// 주요 책임: 병원과 약국 화면을 구분한다.
// 속성: hospital/pharmacy: 검색 대상 값.
enum NearbyCareDestination { hospital, pharmacy }

// Function Name: showNearbyCareOptions
// Description: Opens a safe-area sheet for choosing nearby hospitals or pharmacies.
// Parameters: context (BuildContext): sheet host; userSetting (UserSetting): language selection.
// Returns: Future resolving to the chosen destination, or null when dismissed.
Future<NearbyCareDestination?> showNearbyCareOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) {
  final english = userSetting.isEnglish;
  return showModalBottomSheet<NearbyCareDestination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => MedBuddyOptionSheet(
      children: [
        for (final destination in NearbyCareDestination.values) ...[
          if (destination != NearbyCareDestination.values.first)
            const SizedBox(height: 10),
          _NearbyCareOption(
            destination: destination,
            english: english,
            onTap: () => Navigator.pop(sheetContext, destination),
          ),
        ],
      ],
    ),
  );
}

// 클래스명: _NearbyCareOption
// 역할: 주변 시설 검색 종류 한 개를 표시한다.
// 주요 책임: 종류별 아이콘·제목·설명을 선택 명령과 연결한다.
// 속성: destination (NearbyCareDestination): 대상; english (bool): 언어; onTap (VoidCallback): 선택 명령.
class _NearbyCareOption extends StatelessWidget {
  final NearbyCareDestination destination;
  final bool english;
  final VoidCallback onTap;

  // 함수이름: _NearbyCareOption
  // 함수역할: 검색 대상과 표시 언어·선택 명령을 받는다.
  // 매개변수: destination (NearbyCareDestination): 대상; english (bool): 언어; onTap (VoidCallback): 선택.
  // 반환값: 새 _NearbyCareOption.
  const _NearbyCareOption({
    required this.destination,
    required this.english,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 병원은 진료과·진료시간, 약국은 위치·영업시간 검색으로 설명한다.
  // 매개변수: context (BuildContext): 표시 위치.
  // 반환값: 대상별 MedBuddyOptionTile.
  @override
  Widget build(BuildContext context) {
    final hospital = destination == NearbyCareDestination.hospital;
    final title = hospital
        ? (english ? 'Nearby hospitals' : '근처 병원')
        : (english ? 'Nearby pharmacies' : '근처 약국');
    final subtitle = hospital
        ? (english
              ? 'Find hospitals by specialty and check consultation hours.'
              : '진료과별로 주변 병원을 찾고 진료시간을 확인합니다.')
        : (english
              ? 'Find nearby pharmacies and check opening hours.'
              : '주변 약국의 위치와 영업시간을 확인합니다.');
    return MedBuddyOptionTile(
      inkKey: ValueKey('nearby-care-${destination.name}'),
      icon: hospital
          ? Icons.local_hospital_outlined
          : Icons.storefront_outlined,
      title: title,
      subtitle: subtitle,
      // 글씨 크기는 앱 전역 배율로만 조정하므로 선택지 자체에는 추가 배율을 주지 않는다.
      onTap: onTap,
    );
  }
}
