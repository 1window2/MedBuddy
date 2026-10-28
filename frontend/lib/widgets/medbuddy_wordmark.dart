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
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              MedBuddyColors.pageBackground,
              BlendMode.modulate,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoCrop(source: Rect.fromLTWH(240, 180, 575, 590), width: 46),
                SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LogoCrop(
                      key: Key('brand-wordmark-image'),
                      source: Rect.fromLTWH(175, 800, 754, 160),
                      width: 148,
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
    ),
  );
}

// 저장소의 1080px 원본에서 심볼과 글자 영역만 표시해 가로 로고로 배치한다.
class _LogoCrop extends StatelessWidget {
  const _LogoCrop({super.key, required this.source, required this.width});

  final Rect source;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scale = width / source.width;
    final imageSize = 1080 * scale;
    return SizedBox(
      width: width,
      height: source.height * scale,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: imageSize,
          maxWidth: imageSize,
          minHeight: imageSize,
          maxHeight: imageSize,
          child: Transform.translate(
            offset: Offset(-source.left * scale, -source.top * scale),
            child: Image.asset(
              'assets/app_icon/medbuddy_logo.png',
              width: imageSize,
              height: imageSize,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}
