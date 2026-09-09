// 파일명: medication_image_viewer_boundary.dart
// 역할: 로컬·네트워크 약품 사진의 전체 화면 확대 보기를 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';

import '../entities/medication_image_url_entity.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: MedicationImageViewer
// 역할: 사용 가능한 약품 사진의 확대 보기 진입을 담당한다.
// 주요 책임:
// - 저장된 로컬 사진과 신뢰할 수 있는 네트워크 사진을 동일한 화면에서 처리한다.
// - 사진이 없거나 파일이 사라진 경우 확대 화면을 열지 않는다.
// - 닫기 버튼과 접근성 의미 라벨을 한국어·영어 설정에 맞게 제공한다.
class MedicationImageViewer {
  // 함수이름: MedicationImageViewer._
  // 함수역할: 정적 대화상자 도우미가 외부에서 인스턴스화되지 않도록 제한한다.
  // 매개변수:
  // - 없음.
  // 반환값: 입력 설정이 반영된 MedicationImageViewer 인스턴스.
  const MedicationImageViewer._();

  // 함수이름: show
  // 함수역할: 사용할 수 있는 약품 사진이 있을 때 전체 화면 확대 뷰어를 연다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // - imageUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
  // - localImagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 성공하면 true, 실패하거나 요청을 수행하지 못하면 false로 완료되는 Future.
  static Future<bool> show(
    BuildContext context, {
    required String medicationName,
    String imageUrl = '',
    String localImagePath = '',
    String language = 'ko',
  }) async {
    final source = _MedicationImageSource.resolve(
      imageUrl: imageUrl,
      localImagePath: localImagePath,
    );
    if (source == null) {
      return false;
    }

    final isEnglish = language.trim().toLowerCase().startsWith('en');
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      // 함수이름: show.builder callback
      // 함수역할: 사용 가능한 약품 사진의 확대 보기 진입에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (dialogContext) => _MedicationImageViewerDialog(
        medicationName: medicationName,
        source: source,
        closeLabel: isEnglish ? 'Close enlarged image' : '확대 사진 닫기',
        imageLabel: isEnglish
            ? 'Enlarged image of $medicationName'
            : '$medicationName 확대 사진',
      ),
    );
    return true;
  }
}

// 클래스명: _MedicationImageViewerDialog
// 역할: 로컬·네트워크 약품 사진의 확대·이동·닫기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 로컬·네트워크 약품 사진의 확대·이동·닫기 위젯을 구성한다.
// 속성:
// - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
// - source (_MedicationImageSource): 카메라·갤러리 또는 기존 이미지 입력 출처.
// - closeLabel (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - imageLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
class _MedicationImageViewerDialog extends StatelessWidget {
  final String medicationName;
  final _MedicationImageSource source;
  final String closeLabel;
  final String imageLabel;

  // 함수이름: _MedicationImageViewerDialog
  // 함수역할: 로컬·네트워크 약품 사진의 확대·이동·닫기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // - source (_MedicationImageSource): 카메라·갤러리 또는 기존 이미지 입력 출처.
  // - closeLabel (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - imageLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
  // 반환값: 입력 설정이 반영된 _MedicationImageViewerDialog 인스턴스.
  const _MedicationImageViewerDialog({
    required this.medicationName,
    required this.source,
    required this.closeLabel,
    required this.imageLabel,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 로컬·네트워크 약품 사진의 확대·이동·닫기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 로컬·네트워크 약품 사진의 확대·이동·닫기에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                image: true,
                label: imageLabel,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: Center(child: source.buildImage()),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    key: const Key('medication-image-viewer-close'),
                    tooltip: closeLabel,
                    // 함수이름: build.onPressed callback
                    // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      medicationName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _MedicationImageSource
// 역할: 검증된 네트워크 URL 또는 존재하는 로컬 사진 파일을 담당한다.
// 주요 책임:
// - 존재하는 로컬 사진을 우선하고 없으면 안전한 URL을 사용하며 둘 다 없으면 null을 반환한다.
// - 선택한 로컬 파일 또는 네트워크 사진을 비율 유지로 표시하고 공통 오류 위젯을 연결한다.
// 속성:
// - localFile (File?): 존재 여부를 확인한 로컬 약품 사진 파일.
// - networkUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
class _MedicationImageSource {
  final File? localFile;
  final String networkUrl;

  // 함수이름: _MedicationImageSource._
  // 함수역할: 검증된 네트워크 URL 또는 존재하는 로컬 사진 파일 관련 값을 _MedicationImageSource 인스턴스에 담는다.
  // 매개변수:
  // - localFile (File?): 존재 여부를 확인한 로컬 약품 사진 파일.
  // - networkUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
  // 반환값: 입력 설정이 반영된 _MedicationImageSource 인스턴스.
  const _MedicationImageSource._({this.localFile, this.networkUrl = ''});

  // 함수이름: resolve
  // 함수역할: 존재하는 로컬 사진을 우선하고 없으면 안전한 URL을 사용하며 둘 다 없으면 null을 반환한다.
  // 매개변수:
  // - imageUrl (String): 검증 후 사용할 약품 이미지 네트워크 URL.
  // - localImagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // 반환값: _MedicationImageSource?: 사용 가능한 로컬 또는 네트워크 사진; 둘 다 없으면 null.
  static _MedicationImageSource? resolve({
    required String imageUrl,
    required String localImagePath,
  }) {
    final normalizedPath = localImagePath.trim();
    if (normalizedPath.isNotEmpty) {
      final file = File(normalizedPath);
      if (file.existsSync()) {
        return _MedicationImageSource._(localFile: file);
      }
    }

    final normalizedUrl = safeMedicationImageUrl(imageUrl);
    if (normalizedUrl.isEmpty) {
      return null;
    }
    return _MedicationImageSource._(networkUrl: normalizedUrl);
  }

  // 함수이름: buildImage
  // 함수역할: 선택한 로컬 파일 또는 네트워크 사진을 비율 유지로 표시하고 공통 오류 위젯을 연결한다.
  // 매개변수:
  // - 없음.
  // 반환값: 검증된 네트워크 URL 또는 존재하는 로컬 사진 파일에 쓰는 위젯 트리.
  Widget buildImage() {
    final file = localFile;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: _buildImageError,
      );
    }
    return Image.network(
      networkUrl,
      fit: BoxFit.contain,
      errorBuilder: _buildImageError,
    );
  }

  // 함수이름: _buildImageError
  // 함수역할: 약 사진을 불러오지 못한 영역을 이미지 없음 아이콘으로 대체한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - error (Object): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // - stackTrace (StackTrace?): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
  // 반환값: 검증된 네트워크 URL 또는 존재하는 로컬 사진 파일에 쓰는 위젯 트리.
  static Widget _buildImageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: MedBuddyColors.textLight,
        size: 64,
      ),
    );
  }
}
