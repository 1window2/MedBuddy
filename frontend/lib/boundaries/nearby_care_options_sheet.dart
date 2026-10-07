// 홈에서 병원과 약국 중 검색할 대상을 고르는 공통 선택창.
import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

enum NearbyCareDestination { hospital, pharmacy }

// 기존 약 등록 선택창과 같은 간격·색상·버튼 형태로 검색 대상을 선택한다.
Future<NearbyCareDestination?> showNearbyCareOptions({
  required BuildContext context,
  required UserSetting userSetting,
}) {
  final english = userSetting.language.toLowerCase().startsWith('en');
  return showModalBottomSheet<NearbyCareDestination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
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
            for (final destination in NearbyCareDestination.values) ...[
              if (destination != NearbyCareDestination.values.first)
                const SizedBox(height: 10),
              _NearbyCareOption(
                destination: destination,
                english: english,
                scale: userSetting.contentTextScale,
                onTap: () => Navigator.pop(sheetContext, destination),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _NearbyCareOption extends StatelessWidget {
  final NearbyCareDestination destination;
  final bool english;
  final double scale;
  final VoidCallback onTap;

  const _NearbyCareOption({
    required this.destination,
    required this.english,
    required this.scale,
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
    return Material(
      color: const Color(0xFFF4FFF4),
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        key: ValueKey('nearby-care-${destination.name}'),
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
                hospital
                    ? Icons.local_hospital_outlined
                    : Icons.local_pharmacy_outlined,
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
                        fontWeight: FontWeight.w700,
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
