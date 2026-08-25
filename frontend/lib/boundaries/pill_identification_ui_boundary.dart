// 파일명: pill_identification_ui_boundary.dart
// 역할: 한 장 또는 여러 장의 낱알약 사진 식별과 결과 검토 화면을 제공한다.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/check_saved_medication_control.dart';
import '../controls/identify_pill_batch_control.dart';
import '../controls/identify_pill_control.dart';
import '../controls/resolve_duplicate_pill_selection_control.dart';
import '../entities/identified_pill_save_request_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'medication_schedule_review_ui_boundary.dart';

// 타입명: IdentifiedPillSaveCallback
// 역할: 사용자가 확인한 낱알약 후보와 복약 일정을 기존 저장 흐름으로 전달한다.
typedef IdentifiedPillSaveCallback =
    Future<MedicationSaveResult> Function(
      PillIdentificationCandidate candidate,
      MedicationSchedule medicationSchedule,
    );

// 타입명: IdentifiedPillBatchSaveCallback
// 역할: 사용자가 확인한 여러 낱알약과 일정을 한 번의 저장 흐름으로 전달한다.
typedef IdentifiedPillBatchSaveCallback =
    Future<List<MedicationSaveResult>> Function(
      List<IdentifiedPillSaveRequest> requests,
    );

class PillIdentificationUI extends StatefulWidget {
  final UserSetting userSetting;
  final IdentifyPill? control;
  final IdentifyPillBatch? batchControl;
  final IdentifiedPillSaveCallback? onSaveRequested;
  final IdentifiedPillBatchSaveCallback? onBatchSaveRequested;

  const PillIdentificationUI({
    super.key,
    required this.userSetting,
    this.control,
    this.batchControl,
    this.onSaveRequested,
    this.onBatchSaveRequested,
  });

  @override
  State<PillIdentificationUI> createState() => _PillIdentificationUIState();
}

// 클래스명: _PillPhotoDraft
// 역할: 알약 한 개의 앞·뒷면 사진, 후보 결과, 사용자 선택을 같은 작업 단위로 보관한다.
class _PillPhotoDraft {
  Uint8List? frontImage;
  Uint8List? backImage;
  PillIdentificationResult? result;
  String? selectedItemSeq;
  String errorMessage = '';

  bool get hasFrontImage => frontImage != null;
  bool get hasAnyImage => frontImage != null || backImage != null;

  void clearResult() {
    result = null;
    selectedItemSeq = null;
    errorMessage = '';
  }
}

// 열거형명: _DuplicatePillResolution
// 역할: 같은 약품으로 판정된 사진의 복약 일정을 묶을지 각각 유지할지 표현한다.
enum _DuplicatePillResolution { mergeMatchingSchedules, keepSeparate }

class _PillIdentificationUIState extends State<PillIdentificationUI> {
  late final IdentifyPill _control;
  late final IdentifyPillBatch _batchControl;
  late final bool _ownsControl;
  final ResolveDuplicatePillSelectionControl _duplicateSelectionControl =
      const ResolveDuplicatePillSelectionControl();
  final List<_PillPhotoDraft> _drafts = [_PillPhotoDraft()];
  bool _isAnalyzing = false;
  bool _isSelectingImage = false;
  bool _isSaving = false;
  bool _isBatchSaved = false;
  int _analysisCompletedCount = 0;
  int _analysisTotalCount = 0;
  int _retryingRequestCount = 0;
  Duration? _retryAfter;
  int? _selectingDraftIndex;
  bool? _selectingFront;
  String _errorMessage = '';

  bool get _isBusy => _isAnalyzing || _isSelectingImage || _isSaving;

  bool get _allDraftsReady =>
      _drafts.isNotEmpty && _drafts.every((draft) => draft.hasFrontImage);

  List<int> get _pendingDraftIndexes => [
    for (var index = 0; index < _drafts.length; index += 1)
      if (_drafts[index].hasFrontImage && _drafts[index].result == null) index,
  ];

  bool get _canConfirmAll {
    if (_isBatchSaved || !_allDraftsReady) {
      return false;
    }
    return _drafts.every((draft) {
      final result = draft.result;
      return result != null &&
          result.candidates.isNotEmpty &&
          draft.selectedItemSeq != null;
    });
  }

  @override
  void initState() {
    super.initState();
    _ownsControl = widget.control == null;
    _control = widget.control ?? IdentifyPill();
    _batchControl =
        widget.batchControl ?? IdentifyPillBatch(singlePillControl: _control);
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
    final pendingCount = _pendingDraftIndexes.length;
    final hasVisibleResults = _drafts.any((draft) => draft.result != null);
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
              const SizedBox(height: 16),
              for (var index = 0; index < _drafts.length; index += 1) ...[
                _buildPhotoDraft(index, text, textScale),
                if (index < _drafts.length - 1) const Divider(height: 32),
              ],
              const SizedBox(height: 14),
              _buildAddPhotoActions(text, textScale),
              if (!_allDraftsReady && _drafts.any((draft) => draft.hasAnyImage))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    text.frontPhotoRequiredForEveryPill,
                    style: TextStyle(
                      color: const Color(0xFF9A6700),
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
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
                  onPressed: !_allDraftsReady || pendingCount == 0 || _isBusy
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
                    _isAnalyzing
                        ? text.analysisProgress(
                            completedCount: _analysisCompletedCount,
                            totalCount: _analysisTotalCount,
                            isWaitingForRetry: _retryingRequestCount > 0,
                          )
                        : text.identifyPills(pendingCount),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17 * textScale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              if (_isAnalyzing && _retryingRequestCount > 0) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    text.retryWaitNotice(_retryAfter),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF8A6200),
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (hasVisibleResults) ...[
                const SizedBox(height: 30),
                _buildAllResults(text, textScale),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 함수명: _buildPhotoDraft
  // 역할: 알약 한 개의 앞·뒷면 사진 입력과 개별 오류 상태를 표시한다.
  Widget _buildPhotoDraft(
    int index,
    _PillIdentificationText text,
    double textScale,
  ) {
    final draft = _drafts[index];
    final frontSlotKey = index == 0
        ? const Key('pill-front-image-slot')
        : Key('pill-front-image-slot-$index');
    final backSlotKey = index == 0
        ? const Key('pill-back-image-slot')
        : Key('pill-back-image-slot-$index');
    final frontRemoveKey = index == 0
        ? const Key('remove-pill-front-image-button')
        : Key('remove-pill-front-image-button-$index');
    final backRemoveKey = index == 0
        ? const Key('remove-pill-back-image-button')
        : Key('remove-pill-back-image-button-$index');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text.pillPhotoTitle(index + 1),
                style: TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 15 * textScale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (draft.result != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  text.comparisonComplete,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 12 * textScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_drafts.length > 1)
              IconButton(
                key: Key('remove-pill-photo-set-$index'),
                tooltip: text.removePillPhotoSet(index + 1),
                onPressed: _isBusy ? null : () => _removePhotoDraft(index),
                icon: const Icon(Icons.delete_outline),
                color: MedBuddyColors.textMuted,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PillImageSlot(
                key: frontSlotKey,
                label: text.frontPhoto,
                requiredLabel: text.requiredLabel,
                imageBytes: draft.frontImage,
                isLoading:
                    _isSelectingImage &&
                    _selectingDraftIndex == index &&
                    _selectingFront == true,
                removeButtonKey: frontRemoveKey,
                removeTooltip: text.removePhoto(text.frontPhoto),
                onRemove: draft.frontImage == null || _isBusy
                    ? null
                    : () => _removeImage(index: index, isFront: true),
                onTap: _isBusy
                    ? null
                    : () => _selectImage(
                        draftIndex: index,
                        isFront: true,
                        text: text,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PillImageSlot(
                key: backSlotKey,
                label: text.backPhoto,
                requiredLabel: text.optionalLabel,
                imageBytes: draft.backImage,
                isLoading:
                    _isSelectingImage &&
                    _selectingDraftIndex == index &&
                    _selectingFront == false,
                removeButtonKey: backRemoveKey,
                removeTooltip: text.removePhoto(text.backPhoto),
                onRemove: draft.backImage == null || _isBusy
                    ? null
                    : () => _removeImage(index: index, isFront: false),
                onTap: _isBusy
                    ? null
                    : () => _selectImage(
                        draftIndex: index,
                        isFront: false,
                        text: text,
                      ),
              ),
            ),
          ],
        ),
        if (draft.errorMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ErrorNotice(message: draft.errorMessage),
        ],
      ],
    );
  }

  // 함수명: _buildAddPhotoActions
  // 역할: 카메라로 다음 알약을 추가하거나 갤러리 사진 여러 장을 한꺼번에 등록하게 한다.
  Widget _buildAddPhotoActions(_PillIdentificationText text, double textScale) {
    final occupiedCount = _drafts.where((draft) => draft.hasFrontImage).length;
    final canAddPhotoSet =
        !_isBusy && _drafts.length < IdentifyPillBatch.maxBatchSize;
    final canAddGalleryImages =
        !_isBusy && occupiedCount < IdentifyPillBatch.maxBatchSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('add-pill-photo-set-button'),
          onPressed: canAddPhotoSet ? _addPhotoDraft : null,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(
            text.addAnotherPill,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * textScale,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          key: const Key('add-multiple-pill-images-button'),
          onPressed: canAddGalleryImages
              ? () => _selectMultipleFrontImages(text)
              : null,
          icon: _isSelectingImage && _selectingDraftIndex == null
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_outlined),
          label: Text(
            text.addMultipleFromGallery,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * textScale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          text.batchLimitNotice(IdentifyPillBatch.maxBatchSize),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MedBuddyColors.textSubtle,
            fontSize: 11 * textScale,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildAllResults(_PillIdentificationText text, double textScale) {
    final resultIndexes = [
      for (var index = 0; index < _drafts.length; index += 1)
        if (_drafts[index].result != null) index,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var position = 0;
          position < resultIndexes.length;
          position += 1
        ) ...[
          _buildResultForDraft(resultIndexes[position], text, textScale),
          if (position < resultIndexes.length - 1) const Divider(height: 34),
        ],
        if (resultIndexes.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('confirm-pill-candidate-button'),
              onPressed: !_canConfirmAll || _isBusy
                  ? null
                  : () => _confirmCandidates(text),
              style: OutlinedButton.styleFrom(
                foregroundColor: MedBuddyColors.primaryDark,
                side: const BorderSide(
                  color: MedBuddyColors.primary,
                  width: 1.5,
                ),
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isBatchSaved
                        ? Icons.check_circle_outline
                        : Icons.verified_outlined,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _isBatchSaved
                          ? text.savedComplete
                          : text.confirmSelections(_drafts.length),
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
      ],
    );
  }

  Widget _buildResultForDraft(
    int index,
    _PillIdentificationText text,
    double textScale,
  ) {
    final draft = _drafts[index];
    final result = draft.result!;
    final actionsEnabled = !_isBusy;
    if (result.candidates.isEmpty) {
      return Semantics(
        key: index == 0
            ? const Key('pill-empty-results')
            : Key('pill-empty-results-$index'),
        container: true,
        liveRegion: true,
        label: text.candidateResultsAnnouncement(0),
        child: _EmptyResult(
          text: text,
          textScale: textScale,
          onRetry: actionsEnabled ? () => _prepareRetry(index) : null,
        ),
      );
    }

    return Semantics(
      key: index == 0
          ? const Key('pill-candidate-results')
          : Key('pill-candidate-results-$index'),
      container: true,
      liveRegion: true,
      label: text.candidateResultsAnnouncement(result.candidates.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.candidateTitleForPill(index + 1, result.candidates.length),
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
          if (!result.isConfident ||
              result.observedFeatures.qualityIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ConfidenceNotice(
              key: index == 0
                  ? const Key('pill-confidence-warning')
                  : Key('pill-confidence-warning-$index'),
              message: text.lowConfidenceNotice,
            ),
          ],
          const SizedBox(height: 14),
          for (final candidate in result.candidates) ...[
            _PillCandidateCard(
              candidate: candidate,
              selected: candidate.itemSeq == draft.selectedItemSeq,
              duplicateCount: candidate.itemSeq == draft.selectedItemSeq
                  ? _selectedCandidateCount(candidate)
                  : 1,
              text: text,
              textScale: textScale,
              onTap: actionsEnabled
                  ? () => setState(() {
                      draft.selectedItemSeq = candidate.itemSeq;
                      _isBatchSaved = false;
                    })
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Future<void> _selectImage({
    required int draftIndex,
    required bool isFront,
    required _PillIdentificationText text,
  }) async {
    if (_isBusy || draftIndex < 0 || draftIndex >= _drafts.length) {
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
      _selectingDraftIndex = draftIndex;
      _selectingFront = isFront;
    });

    try {
      final imageBytes = await _control.requestPillImage(source);
      if (imageBytes == null || !mounted || draftIndex >= _drafts.length) {
        return;
      }
      setState(() {
        final draft = _drafts[draftIndex];
        if (isFront) {
          draft.frontImage = imageBytes;
        } else {
          draft.backImage = imageBytes;
        }
        draft.clearResult();
        _isBatchSaved = false;
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
          _selectingDraftIndex = null;
          _selectingFront = null;
        });
      }
    }
  }

  // 함수명: _selectMultipleFrontImages
  // 역할: 갤러리에서 고른 여러 장을 각각 별도의 알약 앞면 사진으로 등록한다.
  Future<void> _selectMultipleFrontImages(_PillIdentificationText text) async {
    if (_isBusy) {
      return;
    }
    final occupiedCount = _drafts.where((draft) => draft.hasFrontImage).length;
    final remainingCapacity = IdentifyPillBatch.maxBatchSize - occupiedCount;
    if (remainingCapacity <= 0) {
      setState(() {
        _errorMessage = text.batchLimitReached(IdentifyPillBatch.maxBatchSize);
      });
      return;
    }

    setState(() {
      _isSelectingImage = true;
      _selectingDraftIndex = null;
      _selectingFront = true;
    });
    try {
      final images = await _control.requestMultiplePillImagesFromGallery(
        limit: remainingCapacity,
      );
      if (!mounted || images.isEmpty) {
        return;
      }
      setState(() {
        for (final image in images) {
          _PillPhotoDraft? emptyDraft;
          for (final draft in _drafts) {
            if (!draft.hasAnyImage) {
              emptyDraft = draft;
              break;
            }
          }
          final target = emptyDraft ?? _PillPhotoDraft();
          if (emptyDraft == null) {
            _drafts.add(target);
          }
          target.frontImage = image;
          target.clearResult();
        }
        _isBatchSaved = false;
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
          _selectingDraftIndex = null;
          _selectingFront = null;
        });
      }
    }
  }

  void _addPhotoDraft() {
    if (_isBusy || _drafts.length >= IdentifyPillBatch.maxBatchSize) {
      return;
    }
    setState(() {
      _drafts.add(_PillPhotoDraft());
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  void _removePhotoDraft(int index) {
    if (_isBusy || _drafts.length <= 1) {
      return;
    }
    setState(() {
      _drafts.removeAt(index);
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  Future<void> _requestIdentification() async {
    final pendingIndexes = _pendingDraftIndexes;
    if (!_allDraftsReady || pendingIndexes.isEmpty) {
      return;
    }
    final text = _PillIdentificationText(widget.userSetting.language);
    setState(() {
      _isAnalyzing = true;
      _isBatchSaved = false;
      _errorMessage = '';
      _analysisCompletedCount = 0;
      _analysisTotalCount = pendingIndexes.length;
      _retryingRequestCount = 0;
      _retryAfter = null;
      for (final index in pendingIndexes) {
        _drafts[index].errorMessage = '';
      }
    });

    try {
      final outcomes = await _batchControl.requestBatchIdentification(
        [
          for (final index in pendingIndexes)
            PillImagePair(
              frontImage: _drafts[index].frontImage!,
              backImage: _drafts[index].backImage,
            ),
        ],
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _analysisCompletedCount = progress.completedCount;
            _analysisTotalCount = progress.totalCount;
            _retryingRequestCount = progress.retryingRequestCount;
            _retryAfter = progress.retryAfter ?? _retryAfter;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        for (final outcome in outcomes) {
          final draft = _drafts[pendingIndexes[outcome.index]];
          final result = outcome.result;
          if (result != null) {
            draft.result = result;
            draft.selectedItemSeq = null;
            draft.errorMessage = '';
          } else {
            draft.result = null;
            draft.selectedItemSeq = null;
            draft.errorMessage = _stateErrorMessage(
              outcome.error ?? StateError('Unknown pill batch failure.'),
              text.requestFailed,
            );
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _stateErrorMessage(error, text.requestFailed);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _retryingRequestCount = 0;
          _retryAfter = null;
        });
      }
    }
  }

  void _removeImage({required int index, required bool isFront}) {
    setState(() {
      final draft = _drafts[index];
      if (isFront) {
        draft.frontImage = null;
      } else {
        draft.backImage = null;
      }
      draft.clearResult();
      _isBatchSaved = false;
      _errorMessage = '';
    });
  }

  void _prepareRetry(int index) {
    setState(() {
      _drafts[index].clearResult();
      _isBatchSaved = false;
    });
  }

  PillIdentificationCandidate? _selectedCandidate(_PillPhotoDraft draft) {
    final selectedItemSeq = draft.selectedItemSeq;
    if (selectedItemSeq == null) {
      return null;
    }
    for (final candidate in draft.result?.candidates ?? const []) {
      if (candidate.itemSeq == selectedItemSeq) {
        return candidate;
      }
    }
    return null;
  }

  // 함수명: _selectedCandidateCount
  // 역할: 현재 선택된 후보 중 같은 품목으로 판정된 사진 수를 계산한다.
  int _selectedCandidateCount(PillIdentificationCandidate target) {
    final selectedCandidates = _drafts
        .map(_selectedCandidate)
        .whereType<PillIdentificationCandidate>();
    return _duplicateSelectionControl.countEquivalentCandidates(
      selectedCandidates,
      target,
    );
  }

  Future<void> _confirmCandidates(_PillIdentificationText text) async {
    final candidates = <PillIdentificationCandidate>[];
    for (final draft in _drafts) {
      final candidate = _selectedCandidate(draft);
      if (candidate == null) {
        return;
      }
      candidates.add(candidate);
    }
    if (candidates.isEmpty) {
      return;
    }

    final duplicateGroups = _duplicateSelectionControl.findDuplicateGroups(
      candidates,
    );
    var duplicateResolution = _DuplicatePillResolution.keepSeparate;
    if (duplicateGroups.isNotEmpty) {
      final selectedResolution = await _chooseDuplicateResolution(
        text: text,
        duplicateGroups: duplicateGroups,
      );
      if (!mounted || selectedResolution == null) {
        return;
      }
      duplicateResolution = selectedResolution;
    }

    final onSaveRequested = widget.onSaveRequested;
    final onBatchSaveRequested = widget.onBatchSaveRequested;
    if (onSaveRequested != null || onBatchSaveRequested != null) {
      await _reviewAndSaveCandidates(
        candidates: candidates,
        onSaveRequested: onSaveRequested,
        onBatchSaveRequested: onBatchSaveRequested,
        duplicateResolution: duplicateResolution,
        text: text,
      );
      return;
    }

    final confirmedCandidates =
        duplicateResolution == _DuplicatePillResolution.mergeMatchingSchedules
        ? _duplicateSelectionControl.uniqueCandidates(candidates)
        : candidates;

    // 저장 콜백이 없는 독립 실행 화면도 사용자가 선택한 중복 처리 방식을 반영한다.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.confirmedTitle),
        content: Text(
          confirmedCandidates.length == 1
              ? text.confirmedMessage(confirmedCandidates.first.itemName)
              : text.confirmedBatchMessage(
                  confirmedCandidates
                      .map((candidate) => candidate.itemName)
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(text.close),
          ),
        ],
      ),
    );
  }

  // 함수명: _chooseDuplicateResolution
  // 역할: 같은 약품 사진을 각각 유지하거나 동일 일정만 묶도록 사용자에게 확인받는다.
  Future<_DuplicatePillResolution?> _chooseDuplicateResolution({
    required _PillIdentificationText text,
    required List<DuplicatePillSelectionGroup> duplicateGroups,
  }) {
    final duplicatePhotoCount = duplicateGroups.fold<int>(
      0,
      (total, group) => total + group.count,
    );
    return showDialog<_DuplicatePillResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.duplicateSelectionTitle),
        content: Text(text.duplicateSelectionMessage(duplicatePhotoCount)),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          TextButton(
            key: const Key('duplicate-pill-cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(text.cancel),
          ),
          OutlinedButton(
            key: const Key('duplicate-pill-keep-separate'),
            onPressed: () =>
                Navigator.pop(context, _DuplicatePillResolution.keepSeparate),
            child: Text(text.keepDuplicateSchedulesSeparate),
          ),
          FilledButton(
            key: const Key('duplicate-pill-merge-matching'),
            onPressed: () => Navigator.pop(
              context,
              _DuplicatePillResolution.mergeMatchingSchedules,
            ),
            child: Text(text.mergeMatchingDuplicateSchedules),
          ),
        ],
      ),
    );
  }

  // 함수명: _reviewAndSaveCandidates
  // 역할:
  // - 선택한 모든 후보에 안전한 임시 복약 기본값을 채워 한 화면에서 검토하게 한다.
  // - 확인된 일정들을 일괄 저장 콜백으로 전달하고 성공·중복·실패 건수를 안내한다.
  Future<void> _reviewAndSaveCandidates({
    required List<PillIdentificationCandidate> candidates,
    required IdentifiedPillSaveCallback? onSaveRequested,
    required IdentifiedPillBatchSaveCallback? onBatchSaveRequested,
    required _DuplicatePillResolution duplicateResolution,
    required _PillIdentificationText text,
  }) async {
    final reviewedSchedules = await showMedicationScheduleReview(
      context: context,
      initialSchedules: [
        for (final candidate in candidates)
          MedicationSchedule(
            medicationName: candidate.itemName,
            prescriptionDate: DateTime.now(),
            dosage: '1정',
            intakeTime: '1회',
            medicationTime: 1,
            scheduleSlotKeys: const [defaultMedicationScheduleSlotKey],
            imageUrl: candidate.imageUrl,
            nameConfidence: candidate.matchScore,
            nameCorrectionSource: 'pill_identification',
          ),
      ],
      userSetting: widget.userSetting,
      purpose: MedicationScheduleReviewPurpose.pillSave,
    );
    if (!mounted || reviewedSchedules == null) {
      return;
    }
    if (reviewedSchedules.length != candidates.length) {
      _showSnackBar(text.medicationSaveFailed);
      return;
    }

    final reviewedRequests = [
      for (var index = 0; index < candidates.length; index += 1)
        IdentifiedPillSaveRequest(
          candidate: candidates[index],
          medicationSchedule: reviewedSchedules[index],
        ),
    ];
    final requests =
        duplicateResolution == _DuplicatePillResolution.mergeMatchingSchedules
        ? _duplicateSelectionControl.mergeEquivalentRequests(reviewedRequests)
        : reviewedRequests;
    final mergedCount = reviewedRequests.length - requests.length;

    setState(() => _isSaving = true);
    List<MedicationSaveResult> results;
    try {
      if (onBatchSaveRequested != null) {
        results = await onBatchSaveRequested(requests);
      } else {
        results = <MedicationSaveResult>[];
        for (final request in requests) {
          results.add(
            await onSaveRequested!(
              request.candidate,
              request.medicationSchedule,
            ),
          );
        }
      }
    } catch (_) {
      results = [
        for (var index = 0; index < requests.length; index += 1)
          MedicationSaveResult(
            status: MedicationSaveStatus.failed,
            message: text.medicationSaveFailed,
          ),
      ];
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
    if (!mounted) {
      return;
    }

    final normalizedResults = results.length == requests.length
        ? results
        : [
            for (var index = 0; index < requests.length; index += 1)
              index < results.length
                  ? results[index]
                  : MedicationSaveResult(
                      status: MedicationSaveStatus.failed,
                      message: text.medicationSaveFailed,
                    ),
          ];
    final savedCount = normalizedResults
        .where((result) => result.status == MedicationSaveStatus.saved)
        .length;
    final duplicateCount = normalizedResults
        .where((result) => result.status == MedicationSaveStatus.duplicate)
        .length;
    final failedCount = normalizedResults
        .where((result) => result.status == MedicationSaveStatus.failed)
        .length;
    setState(() {
      _isBatchSaved = failedCount == 0;
    });

    final resultMessage = normalizedResults.length == 1
        ? switch (normalizedResults.first.status) {
            MedicationSaveStatus.saved => text.medicationSaved,
            MedicationSaveStatus.duplicate => text.medicationAlreadySaved,
            MedicationSaveStatus.failed =>
              normalizedResults.first.message.trim().isEmpty
                  ? text.medicationSaveFailed
                  : normalizedResults.first.message.trim(),
          }
        : text.batchSaveSummary(
            savedCount: savedCount,
            duplicateCount: duplicateCount,
            failedCount: failedCount,
          );
    _showSnackBar(text.withMergedDuplicateSummary(resultMessage, mergedCount));
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      PillIdentificationFailure.rateLimited => text.rateLimited,
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
  final String removeTooltip;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const _PillImageSlot({
    super.key,
    required this.label,
    required this.requiredLabel,
    required this.imageBytes,
    required this.isLoading,
    required this.removeButtonKey,
    required this.removeTooltip,
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
                      dimension: 48,
                      child: IconButton(
                        key: removeButtonKey,
                        tooltip: removeTooltip,
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
  final int duplicateCount;
  final _PillIdentificationText text;
  final double textScale;
  final VoidCallback? onTap;

  const _PillCandidateCard({
    required this.candidate,
    required this.selected,
    required this.duplicateCount,
    required this.text,
    required this.textScale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imprint = [
      candidate.printFront,
      candidate.printBack,
    ].where((value) => value.isNotEmpty).join(' / ');
    return Semantics(
      container: true,
      selected: selected,
      child: Material(
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
                color: selected
                    ? MedBuddyColors.primary
                    : MedBuddyColors.divider,
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
                      if (duplicateCount > 1) ...[
                        const SizedBox(height: 6),
                        Container(
                          key: Key('duplicate-pill-badge-${candidate.itemSeq}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3D6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            text.sameMedicinePhotoCount(duplicateCount),
                            style: TextStyle(
                              color: const Color(0xFF8A5A00),
                              fontSize: 11 * textScale,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
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
      ),
    );
  }
}

class _CandidateImage extends StatelessWidget {
  final String url;

  const _CandidateImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = safeMedicationImageUrl(url);
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
        child: normalizedUrl.isEmpty
            ? placeholder
            : Image.network(
                normalizedUrl,
                fit: BoxFit.contain,
                cacheWidth: 228,
                cacheHeight: 228,
                errorBuilder: (context, error, stackTrace) => placeholder,
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
    return Semantics(
      liveRegion: true,
      child: Container(
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
      ),
    );
  }
}

class _ConfidenceNotice extends StatelessWidget {
  final String message;

  const _ConfidenceNotice({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF0C36A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFF9A6700),
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF6B4B00),
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  final _PillIdentificationText text;
  final double textScale;
  final VoidCallback? onRetry;

  const _EmptyResult({
    required this.text,
    required this.textScale,
    this.onRetry,
  });

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
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(text.retryComparison),
              ),
            ],
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
      isEnglish ? 'Add one photo set per pill' : '알약마다 사진을 따로 추가해주세요';
  String get photoSectionDescription => isEnglish
      ? 'Photograph each pill separately. Keep one pill in focus with its outline visible; adding its reverse side improves matching. You can combine up to 10 pills in one review.'
      : '알약을 한곳에 모아 찍지 말고 한 알씩 선명하게 촬영하세요. 같은 알약의 뒷면을 추가하면 정확도가 높아지며, 최대 10개를 한 번에 검토할 수 있습니다.';
  String pillPhotoTitle(int number) =>
      isEnglish ? 'Pill $number photo' : '알약 $number 사진';
  String get comparisonComplete => isEnglish ? 'Compared' : '비교 완료';
  String removePillPhotoSet(int number) =>
      isEnglish ? 'Remove pill $number photo set' : '알약 $number 사진 묶음 삭제';
  String get addAnotherPill => isEnglish ? 'Add another pill' : '알약 한 개 더 추가';
  String get addMultipleFromGallery =>
      isEnglish ? 'Add multiple pill photos from gallery' : '갤러리에서 여러 알약 사진 추가';
  String batchLimitNotice(int limit) => isEnglish
      ? 'Up to $limit pills per batch. Use one front photo for each pill.'
      : '한 번에 최대 $limit개까지 가능하며, 알약마다 앞면 사진이 한 장씩 필요합니다.';
  String batchLimitReached(int limit) => isEnglish
      ? 'You can compare up to $limit pills at once.'
      : '알약은 한 번에 최대 $limit개까지 비교할 수 있습니다.';
  String get frontPhotoRequiredForEveryPill => isEnglish
      ? 'Add a front photo for every pill before starting the comparison.'
      : '비교를 시작하려면 모든 알약에 앞면 사진을 추가해주세요.';
  String get frontPhoto => isEnglish ? 'Front' : '앞면';
  String get backPhoto => isEnglish ? 'Back' : '뒷면';
  String get requiredLabel => isEnglish ? 'Required' : '필수';
  String get optionalLabel => isEnglish ? 'Optional' : '선택';
  String get camera => isEnglish ? 'Take a photo' : '카메라로 촬영';
  String get gallery => isEnglish ? 'Choose from gallery' : '갤러리에서 선택';
  String identifyPills(int count) {
    final normalizedCount = count < 1 ? 1 : count;
    return isEnglish
        ? 'Find candidates for $normalizedCount pill${normalizedCount == 1 ? '' : 's'}'
        : '알약 $normalizedCount개 후보 찾기';
  }

  String analyzingPills(int count) {
    final normalizedCount = count < 1 ? 1 : count;
    return isEnglish
        ? 'Comparing $normalizedCount pill${normalizedCount == 1 ? '' : 's'}...'
        : '알약 $normalizedCount개 비교 중...';
  }

  String analysisProgress({
    required int completedCount,
    required int totalCount,
    required bool isWaitingForRetry,
  }) {
    final safeTotal = totalCount < 1 ? 1 : totalCount;
    if (isWaitingForRetry) {
      return isEnglish
          ? 'Waiting to retry · $completedCount/$safeTotal completed'
          : '자동 재시도 대기 중 · $completedCount/$safeTotal 완료';
    }
    return isEnglish
        ? 'Comparing pills · $completedCount/$safeTotal completed'
        : '알약 비교 중 · $completedCount/$safeTotal 완료';
  }

  String retryWaitNotice(Duration? retryAfter) {
    final seconds = retryAfter?.inSeconds;
    if (seconds == null || seconds < 1) {
      return isEnglish
          ? 'Request traffic is high. Failed items will retry automatically.'
          : '요청이 많아 잠시 기다린 뒤 실패 항목만 자동으로 다시 시도합니다.';
    }
    return isEnglish
        ? 'Retrying failed items automatically in up to $seconds seconds.'
        : '최대 $seconds초 뒤 실패 항목만 자동으로 다시 시도합니다.';
  }

  String candidateTitle(int count) =>
      isEnglish ? '$count possible matches' : '가능성이 있는 후보 $count개';
  String candidateTitleForPill(int pillNumber, int count) => isEnglish
      ? 'Pill $pillNumber · $count possible matches'
      : '알약 $pillNumber · 가능한 후보 $count개';
  String candidateResultsAnnouncement(int count) => isEnglish
      ? 'Pill identification completed. $count possible matches.'
      : '알약 식별이 완료되었습니다. 가능한 후보는 $count개입니다.';
  String removePhoto(String label) =>
      isEnglish ? 'Remove $label photo' : '$label 사진 삭제';
  String get candidateDescription => isEnglish
      ? 'Select the closest product and verify every printed detail.'
      : '가장 가까운 제품을 선택한 뒤 각인과 제품 정보를 직접 대조하세요.';
  String get lowConfidenceNotice => isEnglish
      ? 'These matches are uncertain or the photo needs extra care. Compare both sides and every imprint before confirming.'
      : '후보 일치도가 낮거나 사진 품질에 주의가 필요합니다. 앞뒷면과 각인 정보를 직접 비교한 뒤 선택하세요.';
  String get similarity => isEnglish ? 'Attribute match' : '속성 일치도';
  String get selected => isEnglish ? 'Selected' : '선택됨';
  String get notSelected => isEnglish ? 'Not selected' : '선택 안 됨';
  String sameMedicinePhotoCount(int count) =>
      isEnglish ? 'Same medicine ×$count' : '동일 약품 사진 $count장';
  String get duplicateSelectionTitle =>
      isEnglish ? 'Review matching medicines' : '동일 약품 사진 확인';
  String duplicateSelectionMessage(int photoCount) => isEnglish
      ? '$photoCount photos were matched to the same medicine. Review every schedule, then choose whether completely identical schedules should be merged. Different doses, dates, or durations will always stay separate.'
      : '같은 약품으로 확인된 사진이 $photoCount장 있습니다. 각 복약 정보를 검토한 뒤, 내용이 완전히 같은 일정만 하나로 묶을지 선택해주세요. 복용량, 날짜 또는 기간이 다르면 항상 별도로 유지됩니다.';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get keepDuplicateSchedulesSeparate =>
      isEnglish ? 'Keep separately' : '각각 유지';
  String get mergeMatchingDuplicateSchedules =>
      isEnglish ? 'Merge identical schedules' : '같은 일정만 묶기';
  String confirmSelections(int count) => isEnglish
      ? count == 1
            ? 'Confirm selected candidate'
            : 'Review and save $count selected pills'
      : count == 1
      ? '선택한 후보 확인'
      : '선택한 알약 $count개 검토 후 저장';
  String get savedComplete => isEnglish ? 'Saved' : '저장 완료';
  String get confirmedTitle => isEnglish ? 'Candidate selected' : '후보 선택 완료';
  String confirmedMessage(String name) => isEnglish
      ? '$name was selected as a possible match. This is not a diagnosis; verify it with the package or a pharmacist.'
      : '$name을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 포장 정보 또는 약사에게 확인하세요.';
  String confirmedBatchMessage(List<String> names) => isEnglish
      ? '${names.join(', ')} were selected as possible matches. These are not confirmed results; verify each package or ask a pharmacist.'
      : '${names.join(', ')}을(를) 가능한 후보로 선택했습니다. 확정 결과가 아니므로 각 포장 정보 또는 약사에게 확인하세요.';
  String get medicationSaved =>
      isEnglish ? 'Medication plan saved.' : '복약 정보를 저장했습니다.';
  String get medicationAlreadySaved => isEnglish
      ? 'The same medication plan is already saved.'
      : '같은 복약 정보가 이미 저장되어 있습니다.';
  String get medicationSaveFailed =>
      isEnglish ? 'Could not save the medication plan.' : '복약 정보를 저장하지 못했습니다.';
  String batchSaveSummary({
    required int savedCount,
    required int duplicateCount,
    required int failedCount,
  }) => isEnglish
      ? 'Saved $savedCount, already saved $duplicateCount, failed $failedCount.'
      : '저장 $savedCount개, 기존 정보 $duplicateCount개, 실패 $failedCount개입니다.';
  String withMergedDuplicateSummary(String resultMessage, int mergedCount) {
    if (mergedCount < 1) {
      return resultMessage;
    }
    return isEnglish
        ? 'Merged $mergedCount identical schedule${mergedCount == 1 ? '' : 's'}. $resultMessage'
        : '동일한 복약 일정 $mergedCount개를 하나로 묶었습니다. $resultMessage';
  }

  String get close => isEnglish ? 'Close' : '닫기';
  String get noCandidates => isEnglish
      ? 'No reliable candidates were found. Retake both sides more clearly.'
      : '신뢰할 수 있는 후보를 찾지 못했습니다. 앞뒷면을 더 선명하게 다시 촬영해주세요.';
  String get retryComparison =>
      isEnglish ? 'Compare this pill again' : '이 알약 다시 비교';
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
  String get rateLimited => isEnglish
      ? 'There were too many requests. Please retry the failed pill shortly.'
      : '요청이 많아 식별하지 못했습니다. 실패한 알약만 잠시 후 다시 시도해주세요.';
  String get serviceUnavailable => isEnglish
      ? 'The pill identification service is temporarily unavailable.'
      : '알약 식별 서비스에 일시적으로 연결할 수 없습니다.';
  String get invalidResponse => isEnglish
      ? 'The pill identification response was invalid. Please try again.'
      : '알약 식별 응답을 처리하지 못했습니다. 다시 시도해주세요.';
}
