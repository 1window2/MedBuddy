// 파일명: medbuddy_wordmark.dart
// 역할: 앱 이름과 브랜드 이미지를 하나의 접근 가능한 머리글로 표시한다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedBuddyWordmark
// 역할: 브랜드 마크·앱 이름·보조 문구를 공통 머리글로 표시한다.
// 주요 책임: 제한된 너비 안에서 비율을 유지하고 화면 읽기에 앱 이름을 한 번 제공한다.
// 속성: 고유 상태 없음. 이미지 경로와 기준 크기는 build에 고정되어 있다.
class MedBuddyWordmark extends StatelessWidget {
  // 함수이름: MedBuddyWordmark
  // 함수역할: 별도 입력 데이터 없이 공통 브랜드 머리글을 만든다.
  // 매개변수: key (Key?): 위젯 식별 키.
  // 반환값: 상태 없는 브랜드 위젯.
  const MedBuddyWordmark({super.key});

  // Function Name: build
  // Description: Scales the fixed brand composition down within a 52px header and exposes one MedBuddy image label.
  // Parameters: context (BuildContext): Current widget context.
  // Returns: A left-aligned mark/name/tagline composition; decorative images and tagline do not repeat accessibility labels.
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
// Class Name: _BrandImage
// Role: Displays one pre-sized transparent brand bitmap.
// Responsibilities: Keep layout stable before decoding and leave accessibility naming to the parent brand component.
// Attributes: asset (String): Bundle path; width/height (double): Fixed logical dimensions.
class _BrandImage extends StatelessWidget {
  // Function Name: _BrandImage
  // Description: Configures one bundled brand image with dimensions matching its source aspect ratio.
  // Parameters: asset (String): Image path; key (Key?): Identity; width/height (double): Logical size.
  // Returns: A stateless image component with no independent accessibility label.
  const _BrandImage(
    this.asset, {
    super.key,
    required this.width,
    required this.height,
  });

  final String asset;
  final double width;
  final double height;

  // Function Name: build
  // Description: Loads the brand bitmap at fixed dimensions using contain fit and medium filtering.
  // Parameters: context (BuildContext): Asset resolution context.
  // Returns: An Image.asset excluded from semantics; ordinary Flutter asset-load failure handling applies.
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
