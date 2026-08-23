// 파일명: medication_image_viewer_boundary.dart
// 역할: 여러 복약 화면에서 약품 사진을 확대해 확인하는 공통 화면을 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';

import '../entities/medication_image_url_entity.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: MedicationImageViewer
// 역할: 로컬 또는 공공데이터 약품 사진을 전체 화면에서 확대·이동할 수 있게 보여준다.
// 주요 책임:
// - 저장된 로컬 사진과 신뢰할 수 있는 네트워크 사진을 동일한 화면에서 처리한다.
// - 사진이 없거나 파일이 사라진 경우 확대 화면을 열지 않는다.
// - 닫기 버튼과 접근성 의미 라벨을 한국어·영어 설정에 맞게 제공한다.
class MedicationImageViewer {
  const MedicationImageViewer._();

  // 함수명: show
  // 역할: 사용할 수 있는 약품 사진이 있을 때 전체 화면 확대 뷰어를 연다.
  // 반환값: 사진이 없으면 false, 확대 화면을 열었으면 true
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

class _MedicationImageViewerDialog extends StatelessWidget {
  final String medicationName;
  final _MedicationImageSource source;
  final String closeLabel;
  final String imageLabel;

  const _MedicationImageViewerDialog({
    required this.medicationName,
    required this.source,
    required this.closeLabel,
    required this.imageLabel,
  });

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

class _MedicationImageSource {
  final File? localFile;
  final String networkUrl;

  const _MedicationImageSource._({this.localFile, this.networkUrl = ''});

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
