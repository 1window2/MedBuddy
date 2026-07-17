import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/identify_pill_control.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

class PillIdentificationUI extends StatefulWidget {
  final UserSetting userSetting;
  final IdentifyPill? control;

  const PillIdentificationUI({
    super.key,
    required this.userSetting,
    this.control,
  });

  @override
  State<PillIdentificationUI> createState() => _PillIdentificationUIState();
}

class _PillIdentificationUIState extends State<PillIdentificationUI> {
  late final IdentifyPill _control;
  late final bool _ownsControl;
  Uint8List? _frontImage;
  Uint8List? _backImage;
  PillIdentificationResult? _result;
  String? _selectedItemSeq;
  bool _isAnalyzing = false;
  bool _isSelectingImage = false;
  bool? _selectingFront;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? IdentifyPill();
  }

  @override
  void dispose() {
    if (_ownsControl) {
      _control.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _PillIdentificationText(widget.userSetting.language);
    final textScale = widget.userSetting.contentTextScale;
    final isBusy = _isAnalyzing || _isSelectingImage;
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      appBar: AppBar(
        backgroundColor: MedBuddyColors.pageBackground,
        foregroundColor: MedBuddyColors.textStrong,
        elevation: 0,
        title: Text(
          text.title,
          style: TextStyle(
            fontSize: 20 * textScale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SafetyNotice(text: text, textScale: textScale),
              const SizedBox(height: 22),
              Text(
                text.photoSectionTitle,
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 18 * textScale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.photoSectionDescription,
                style: TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 13 * textScale,
                  height: 1.45,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PillImageSlot(
                      key: const Key('pill-front-image-slot'),
                      label: text.frontPhoto,
                      requiredLabel: text.requiredLabel,
                      imageBytes: _frontImage,
                      isLoading: _isSelectingImage && _selectingFront == true,
                      removeButtonKey:
                          const Key('remove-pill-front-image-button'),
                      onRemove: _frontImage == null || isBusy
                          ? null
                          : () => _removeImage(isFront: true),
                      onTap: isBusy
                          ? null
                          : () => _selectImage(isFront: true, text: text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PillImageSlot(
                      key: const Key('pill-back-image-slot'),
                      label: text.backPhoto,
                      requiredLabel: text.optionalLabel,
                      imageBytes: _backImage,
                      isLoading: _isSelectingImage && _selectingFront == false,
                      removeButtonKey:
                          const Key('remove-pill-back-image-button'),
                      onRemove: _backImage == null || isBusy
                          ? null
                          : () => _removeImage(isFront: false),
                      onTap: isBusy
                          ? null
                          : () => _selectImage(isFront: false, text: text),
                    ),
                  ),
                ],
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ErrorNotice(message: _errorMessage),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  key: const Key('identify-pill-button'),
                  onPressed: _frontImage == null || isBusy
                      ? null
                      : _requestIdentification,
                  style: FilledButton.styleFrom(
                    backgroundColor: MedBuddyColors.primary,
                    disabledBackgroundColor: MedBuddyColors.outline,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _isAnalyzing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _isAnalyzing ? text.analyzing : text.identify,
                    style: TextStyle(
                      fontSize: 17 * textScale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 30),
                _buildResults(text, textScale),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(_PillIdentificationText text, double textScale) {
    final result = _result!;
    final actionsEnabled = !_isAnalyzing && !_isSelectingImage;
    if (result.candidates.isEmpty) {
      return _EmptyResult(text: text, textScale: textScale);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.candidateTitle(result.candidates.length),
          style: TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 19 * textScale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text.candidateDescription,
          style: TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 13 * textScale,
            height: 1.4,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        for (final candidate in result.candidates) ...[
          _PillCandidateCard(
            candidate: candidate,
            selected: candidate.itemSeq == _selectedItemSeq,
            text: text,
            textScale: textScale,
            onTap: actionsEnabled
                ? () => setState(() {
                      _selectedItemSeq = candidate.itemSeq;
                    })
                : null,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('confirm-pill-candidate-button'),
            onPressed: !actionsEnabled || _selectedItemSeq == null
                ? null
                : () => _confirmCandidate(text),
            style: OutlinedButton.styleFrom(
              foregroundColor: MedBuddyColors.primaryDark,
              side: const BorderSide(color: MedBuddyColors.primary, width: 1.5),
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_outlined),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text.confirmSelection,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16 * textScale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectImage({
    required bool isFront,
    required _PillIdentificationText text,
  }) async {
    if (_isAnalyzing || _isSelectingImage) {
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ImageSourceOption(
                icon: Icons.photo_camera_outlined,
                title: text.camera,
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _ImageSourceOption(
                icon: Icons.photo_library_outlined,
                title: text.gallery,
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) {
      return;
    }
    setState(() {
      _isSelectingImage = true;
      _selectingFront = isFront;
    });

    try {
      final imageBytes = await _control.requestPillImage(source);
      if (imageBytes == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (isFront) {
          _frontImage = imageBytes;
        } else {
          _backImage = imageBytes;
        }
        _result = null;
        _selectedItemSeq = null;
        _errorMessage = '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _stateErrorMessage(error, text.imageSelectionFailed);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingImage = false;
          _selectingFront = null;
        });
      }
    }
  }

  Future<void> _requestIdentification() async {
    final frontImage = _frontImage;
    if (frontImage == null) {
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _selectedItemSeq = null;
      _errorMessage = '';
    });

    try {
      final result = await _control.requestPillIdentification(
        frontImage: frontImage,
        backImage: _backImage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _stateErrorMessage(
          error,
          _PillIdentificationText(widget.userSetting.language).requestFailed,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  void _removeImage({required bool isFront}) {
    setState(() {
      if (isFront) {
        _frontImage = null;
      } else {
        _backImage = null;
      }
      _result = null;
      _selectedItemSeq = null;
      _errorMessage = '';
    });
  }

  Future<void> _confirmCandidate(_PillIdentificationText text) async {
    PillIdentificationCandidate? candidate;
    for (final item in _result?.candidates ?? const []) {
      if (item.itemSeq == _selectedItemSeq) {
        candidate = item;
        break;
      }
    }
    if (candidate == null) {
      return;
    }
    final confirmedCandidate = candidate;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.confirmedTitle),
        content: Text(text.confirmedMessage(confirmedCandidate.itemName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(text.close),
          ),
        ],
      ),
    );
  }

  String _stateErrorMessage(Object error, String fallback) {
    if (error is! PillIdentificationException) {
      return fallback;
    }
    final text = _PillIdentificationText(widget.userSetting.language);
    return switch (error.failure) {
      PillIdentificationFailure.emptyImage => text.emptyImage,
      PillIdentificationFailure.oversizedImage => text.oversizedImage,
      PillIdentificationFailure.timedOut => text.timedOut,
      PillIdentificationFailure.invalidPhoto => text.invalidPhoto,
      PillIdentificationFailure.serviceUnavailable => text.serviceUnavailable,
      PillIdentificationFailure.invalidResponse => text.invalidResponse,
      PillIdentificationFailure.fileUnreadable => text.imageSelectionFailed,
    };
  }
}

class _SafetyNotice extends StatelessWidget {
  final _PillIdentificationText text;
  final double textScale;

  const _SafetyNotice({required this.text, required this.textScale});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF0C36A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF9A6700), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.safetyNotice,
              style: TextStyle(
                color: const Color(0xFF6B4B00),
                fontSize: 13 * textScale,
                height: 1.45,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillImageSlot extends StatelessWidget {
  final String label;
  final String requiredLabel;
  final Uint8List? imageBytes;
  final bool isLoading;
  final Key removeButtonKey;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const _PillImageSlot({
    super.key,
    required this.label,
    required this.requiredLabel,
    required this.imageBytes,
    required this.isLoading,
    required this.removeButtonKey,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 174,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: imageBytes == null
                  ? MedBuddyColors.outline
                  : MedBuddyColors.primary,
              width: imageBytes == null ? 1.4 : 2,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          requiredLabel,
                          style: const TextStyle(
                            color: MedBuddyColors.textSubtle,
                            fontSize: 11,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (imageBytes != null)
                    SizedBox.square(
                      dimension: 28,
                      child: IconButton(
                        key: removeButtonKey,
                        tooltip: MaterialLocalizations.of(context)
                            .deleteButtonTooltip,
                        padding: EdgeInsets.zero,
                        iconSize: 19,
                        color: MedBuddyColors.textMuted,
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageBytes == null)
                        const ColoredBox(
                          color: MedBuddyColors.surfaceSubtle,
                          child: Center(
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              color: MedBuddyColors.primary,
                              size: 34,
                            ),
                          ),
                        )
                      else
                        Image.memory(
                          imageBytes!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          cacheWidth: 900,
                        ),
                      if (isLoading)
                        const ColoredBox(
                          color: Color(0xB3FFFFFF),
                          child: Center(
                            child: CircularProgressIndicator(
                              key: Key('pill-image-loading-indicator'),
                              strokeWidth: 2.4,
                              color: MedBuddyColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillCandidateCard extends StatelessWidget {
  final PillIdentificationCandidate candidate;
  final bool selected;
  final _PillIdentificationText text;
  final double textScale;
  final VoidCallback? onTap;

  const _PillCandidateCard({
    required this.candidate,
    required this.selected,
    required this.text,
    required this.textScale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imprint = [candidate.printFront, candidate.printBack]
        .where((value) => value.isNotEmpty)
        .join(' / ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? MedBuddyColors.primary : MedBuddyColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CandidateImage(url: candidate.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 15 * textScale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    if (candidate.manufacturer.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        candidate.manufacturer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MedBuddyColors.textSubtle,
                          fontSize: 12 * textScale,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${text.similarity}: '
                      '${(candidate.matchScore * 100).round()}%'
                      '${imprint.isEmpty ? '' : '  ·  $imprint'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.primaryDark,
                        fontSize: 12 * textScale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? MedBuddyColors.primary
                    : MedBuddyColors.textLight,
                semanticLabel: selected ? text.selected : text.notSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateImage extends StatelessWidget {
  final String url;

  const _CandidateImage({required this.url});

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: MedBuddyColors.surfaceSubtle,
      child: Center(
        child: Icon(Icons.medication_outlined, color: MedBuddyColors.textLight),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: 76,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.contain,
                cacheWidth: 228,
                cacheHeight: 228,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (context, child, progress) {
                  return progress == null ? child : placeholder;
                },
              ),
      ),
    );
  }
}

class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ImageSourceOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: MedBuddyColors.surfaceSubtle,
      leading: Icon(icon, color: MedBuddyColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String message;

  const _ErrorNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFB42318), height: 1.4),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  final _PillIdentificationText text;
  final double textScale;

  const _EmptyResult({required this.text, required this.textScale});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const Icon(
              Icons.search_off,
              color: MedBuddyColors.textLight,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              text.noCandidates,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * textScale,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillIdentificationText {
  final String language;

  const _PillIdentificationText(this.language);

  bool get isEnglish => language == 'en';
  String get title => isEnglish ? 'Identify a Pill' : '알약 식별';
  String get safetyNotice => isEnglish
      ? 'Photos are analyzed by an external AI and are not stored by MedBuddy. Matching only suggests candidates; verify the package or ask a pharmacist.'
      : '사진은 외부 AI로 분석되며 MedBuddy에 저장되지 않습니다. 비교 결과는 후보일 뿐이므로 포장 정보 또는 약사에게 확인하세요.';
  String get photoSectionTitle =>
      isEnglish ? 'Photograph one pill' : '알약 한 개를 촬영해주세요';
  String get photoSectionDescription => isEnglish
      ? 'Keep one pill in focus with its surface and outline visible. Any background color or texture is acceptable. A reverse-side photo improves matching.'
      : '알약 한 개에 초점을 맞추고 표면과 윤곽이 구분되도록 촬영하세요. 배경의 색이나 재질은 상관없습니다. 뒷면 사진을 추가하면 식별 정확도가 높아집니다.';
  String get frontPhoto => isEnglish ? 'Front' : '앞면';
  String get backPhoto => isEnglish ? 'Back' : '뒷면';
  String get requiredLabel => isEnglish ? 'Required' : '필수';
  String get optionalLabel => isEnglish ? 'Optional' : '선택';
  String get camera => isEnglish ? 'Take a photo' : '카메라로 촬영';
  String get gallery => isEnglish ? 'Choose from gallery' : '갤러리에서 선택';
  String get identify => isEnglish ? 'Find candidates' : '후보 찾기';
  String get analyzing => isEnglish ? 'Comparing...' : '비교 중...';
  String candidateTitle(int count) =>
      isEnglish ? '$count possible matches' : '가능성이 있는 후보 $count개';
  String get candidateDescription => isEnglish
      ? 'Select the closest product and verify every printed detail.'
      : '가장 가까운 제품을 선택한 뒤 각인과 제품 정보를 직접 대조하세요.';
  String get similarity => isEnglish ? 'Attribute match' : '속성 일치도';
  String get selected => isEnglish ? 'Selected' : '선택됨';
  String get notSelected => isEnglish ? 'Not selected' : '선택 안 됨';
  String get confirmSelection =>
      isEnglish ? 'Confirm selected candidate' : '선택한 후보 확인';
  String get confirmedTitle => isEnglish ? 'Candidate selected' : '후보 선택 완료';
  String confirmedMessage(String name) => isEnglish
      ? '$name was selected as a possible match. This is not a diagnosis; verify it with the package or a pharmacist.'
      : '$name을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 포장 정보 또는 약사에게 확인하세요.';
  String get close => isEnglish ? 'Close' : '닫기';
  String get noCandidates => isEnglish
      ? 'No reliable candidates were found. Retake both sides more clearly.'
      : '신뢰할 수 있는 후보를 찾지 못했습니다. 앞뒷면을 더 선명하게 다시 촬영해주세요.';
  String get imageSelectionFailed =>
      isEnglish ? 'Could not read the selected image.' : '선택한 이미지를 읽지 못했습니다.';
  String get requestFailed => isEnglish
      ? 'Pill identification failed. Please try again.'
      : '알약 식별에 실패했습니다. 다시 시도해주세요.';
  String get emptyImage =>
      isEnglish ? 'The selected image is empty.' : '선택한 이미지가 비어 있습니다.';
  String get oversizedImage => isEnglish
      ? 'Each pill image must be 10 MB or smaller.'
      : '알약 이미지는 장당 10MB 이하여야 합니다.';
  String get timedOut => isEnglish
      ? 'Pill identification timed out. Please try again.'
      : '알약 식별 시간이 초과되었습니다. 다시 시도해주세요.';
  String get invalidPhoto => isEnglish
      ? 'The pill could not be distinguished. Avoid fingers, strong glare, and occlusion, then retake the photo in focus.'
      : '알약을 구분할 수 없습니다. 손가락, 강한 반사, 가림을 피하고 초점을 맞춰 다시 촬영해주세요.';
  String get serviceUnavailable => isEnglish
      ? 'The pill identification service is temporarily unavailable.'
      : '알약 식별 서비스에 일시적으로 연결할 수 없습니다.';
  String get invalidResponse => isEnglish
      ? 'The pill identification response was invalid. Please try again.'
      : '알약 식별 응답을 처리하지 못했습니다. 다시 시도해주세요.';
}
