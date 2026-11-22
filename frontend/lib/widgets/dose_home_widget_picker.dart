// 파일명: dose_home_widget_picker.dart
// 역할: 기본·확장 위젯의 실제 모양을 함께 보여주고 고른 크기만 반환한다.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/dose_home_widget_service.dart';
import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: DoseHomeWidgetPicker
// 역할: 위젯 미리보기를 메모리에서만 표시한다. 약 기록이나 계정 설정은 바꾸지 않는다.
class DoseHomeWidgetPicker extends StatefulWidget {
  const DoseHomeWidgetPicker({super.key, required this.isEnglish});
  final bool isEnglish;

  @override
  State<DoseHomeWidgetPicker> createState() => _DoseHomeWidgetPickerState();
}

class _DoseHomeWidgetPickerState extends State<DoseHomeWidgetPicker> {
  late Future<Map<String, Uint8List>> _images;

  @override
  void initState() {
    super.initState();
    _images = _load();
  }

  // 함수역할: 선택창을 열거나 재시도할 때 두 크기의 미리보기를 한 번씩 요청한다.
  Future<Map<String, Uint8List>> _load() =>
      DoseHomeWidget.previewImages(widget.isEnglish ? 'en' : 'ko');

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: KeepWordsText(
                    widget.isEnglish
                        ? 'Add medication widget'
                        : '홈 화면 복약 위젯 추가',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: widget.isEnglish ? 'Close' : '닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, Uint8List>>(
            future: _images,
            builder: (context, snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final size in DoseHomeWidgetSize.values) ...[
                  _preview(context, size, snapshot),
                  if (size == DoseHomeWidgetSize.compact)
                    const SizedBox(height: 16),
                ],
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: KeepWordsText(
                            widget.isEnglish
                                ? 'Preview unavailable'
                                : '미리보기를 불러오지 못했습니다.',
                            style: const TextStyle(
                              fontSize: 14,
                              color: MedBuddyColors.textMuted,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('retry-widget-previews'),
                          tooltip: widget.isEnglish ? 'Retry' : '다시 시도',
                          onPressed: () {
                            setState(() {
                              _images = _load();
                            });
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // 함수역할: 미리보기 전체를 하나의 선택 대상으로 만들고 이미지 안의 가짜 조작은 차단한다.
  Widget _preview(
    BuildContext context,
    DoseHomeWidgetSize size,
    AsyncSnapshot<Map<String, Uint8List>> snapshot,
  ) {
    final expanded = size == DoseHomeWidgetSize.expanded;
    final label = expanded ? '4 x 3' : '4 x 1';
    final name = expanded
        ? (widget.isEnglish ? 'Expanded' : '확장')
        : (widget.isEnglish ? 'Default' : '기본');
    final bytes = snapshot.data?[size.name];
    return Semantics(
      button: true,
      label: '$label, $name',
      child: Material(
        color: MedBuddyColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MedBuddyColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('doseHomeWidgetSize-${size.name}'),
          onTap: () => Navigator.pop(context, size),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: KeepWordsText(
                          '$label  $name',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: MedBuddyColors.primaryDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ExcludeSemantics(
                  child: AspectRatio(
                    aspectRatio: 360 / (expanded ? 300 : 80),
                    child: bytes != null
                        ? Image.memory(
                            bytes,
                            key: ValueKey('dose-widget-preview-${size.name}'),
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          )
                        : Center(
                            child: snapshot.hasError
                                ? const Icon(
                                    Icons.widgets_outlined,
                                    color: MedBuddyColors.textMuted,
                                  )
                                : const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
