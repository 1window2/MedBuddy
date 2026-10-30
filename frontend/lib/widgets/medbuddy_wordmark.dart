import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

class MedBuddyWordmark extends StatelessWidget {
  const MedBuddyWordmark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'MedBuddy',
    image: true,
    child: SizedBox(
      height: 52,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandImage(
                'assets/brand/medbuddy_mark.png',
                width: 46,
                height: 47.3,
              ),
              SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandImage(
                    'assets/brand/medbuddy_name.png',
                    key: Key('brand-wordmark-image'),
                    width: 148,
                    height: 29.3,
                  ),
                  SizedBox(height: 2),
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 148,
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'SMART MEDICATION CARE',
                          key: Key('brand-tagline'),
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: MedBuddyColors.primaryDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// 로고 원본에서 잘라낸 투명 이미지(3배 해상도, scripts/generate_android_icons.py가 생성)를
// 그린다. 크기는 이미지 비율대로 미리 정해 디코딩 전후에 배치가 흔들리지 않게 한다.
class _BrandImage extends StatelessWidget {
  const _BrandImage(
    this.asset, {
    super.key,
    required this.width,
    required this.height,
  });

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: width,
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}
