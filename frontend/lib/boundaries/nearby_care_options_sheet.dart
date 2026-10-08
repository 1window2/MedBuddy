// 홈에서 병원과 약국 중 검색할 대상을 고르는 공통 선택창.
import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../widgets/medbuddy_option_sheet.dart';

enum NearbyCareDestination { hospital, pharmacy }

// 기존 약 등록 선택창과 같은 간격·색상·버튼 형태로 검색 대상을 선택한다.
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

class _NearbyCareOption extends StatelessWidget {
  final NearbyCareDestination destination;
  final bool english;
  final VoidCallback onTap;

  const _NearbyCareOption({
    required this.destination,
    required this.english,
    required this.onTap,
  });

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
          : Icons.local_pharmacy_outlined,
      title: title,
      subtitle: subtitle,
      // 글씨 크기는 앱 전역 배율로만 조정하므로 선택지 자체에는 추가 배율을 주지 않는다.
      onTap: onTap,
    );
  }
}
