// 파일명: photo_dose_recording_ui_boundary.dart
// 역할: 사진으로 복용 기록 화면. 손에 든 알약을 찍으면 서버 계획대로 필요한 질문만 묻고, 큰 확인 화면
//   한 번으로 기록한다. 규칙과 화면 구성은 docs/Photo Dose Recording.md를 따른다.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controls/identify_pill_control.dart';
import '../controls/medication_history_control.dart';
import '../controls/photo_dose_control.dart';
import '../entities/medication_slot_label.dart';
import '../entities/photo_dose_plan_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_response_parser.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/keep_words_text.dart';
import '../widgets/medication_thumbnail.dart';

// 열거형: _Stage
// 역할: 화면 단계. 한 번에 하나만 보인다.
enum _Stage { starting, analyzing, question, confirm, recording, done, problem }

// 열거형: PhotoDoseProblem
// 역할: 기록하지 못하는 이유. 원인과 다음 행동만 보인다.
enum PhotoDoseProblem {
  noMedicines,
  noPills,
  nothingToRecord,
  pendingQueue,
  planChanged,
  connection,
}

// 클래스명: PhotoDoseRecordingUI
// 역할: 사진으로 복용 기록 흐름 전체.
// 주요 책임: 카메라, 알약 분석, 계획 질문, 확인, 기록 후 앱 상태 갱신 요청을 차례로 맡는다.
// 속성: userSetting: 언어; hasOwnMedicines: 본인 약이 있는지; onBeforePlan: 첫 계획 전 복용 기록 큐 전송;
//   hasPendingOverlap: 기록할 묶음과 겹치는 미전송 기록이 있는지; onRecorded: 기록 뒤 일정·알림 갱신;
//   onRegisterRequested: 본인 약이 없을 때 약 등록 화면으로; 나머지는 테스트 주입용이다.
class PhotoDoseRecordingUI extends StatefulWidget {
  final UserSetting userSetting;
  final bool hasOwnMedicines;
  final Future<void> Function() onBeforePlan;
  final bool Function(PhotoDosePlan plan) hasPendingOverlap;
  final Future<void> Function(PhotoDoseRecordResult result) onRecorded;
  final VoidCallback? onRegisterRequested;
  final IdentifyPill? identifyPill;
  final PhotoDoseControl? photoDoseControl;
  final Future<Uint8List?> Function()? takePhoto;

  const PhotoDoseRecordingUI({
    super.key,
    required this.userSetting,
    required this.hasOwnMedicines,
    required this.onBeforePlan,
    required this.hasPendingOverlap,
    required this.onRecorded,
    this.onRegisterRequested,
    this.identifyPill,
    this.photoDoseControl,
    this.takePhoto,
  });

  @override
  State<PhotoDoseRecordingUI> createState() => _PhotoDoseRecordingUIState();
}

class _PhotoDoseRecordingUIState extends State<PhotoDoseRecordingUI> {
  late final IdentifyPill _identify = widget.identifyPill ?? IdentifyPill();
  late final PhotoDoseControl _control =
      widget.photoDoseControl ?? PhotoDoseControl();
  late final _PhotoDoseText _text = _PhotoDoseText(
    isEnglishLanguage(widget.userSetting.language),
  );

  _Stage _stage = _Stage.starting;
  PhotoDoseProblem? _problem;
  Uint8List? _photo;
  double _photoAspect = 4 / 3;
  List<MultiplePillObservation> _observations = const [];
  final Map<int, Uint8List> _crops = {};
  List<Map<String, dynamic>> _pills = const [];
  final Map<int, int?> _answers = {};
  PhotoDosePlan? _plan;
  List<PhotoDosePill> _questions = const [];
  int _questionIndex = 0;
  String? _operationId;
  PhotoDoseRecordResult? _result;
  DateTime _confirmShownAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _cancelled = false;
  Future<void>? _flush;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _cancelled = true;
    if (widget.photoDoseControl == null) _control.dispose();
    super.dispose();
  }

  // 함수이름: _start
  // 함수역할: 본인 약을 확인하고 카메라를 연다. 그동안 쌓인 복용 기록 큐를 먼저 보낸다.
  // 매개변수: 없음. 반환값: 단계 진행 완료.
  Future<void> _start() async {
    if (!widget.hasOwnMedicines) {
      _show(_Stage.problem, PhotoDoseProblem.noMedicines);
      return;
    }
    _flush = widget.onBeforePlan().catchError((_) {});
    Uint8List? photo;
    try {
      photo = widget.takePhoto != null
          ? await widget.takePhoto!()
          : await _identify.requestPillImage(ImageSource.camera);
    } catch (_) {
      if (mounted) _show(_Stage.problem, PhotoDoseProblem.connection);
      return;
    }
    if (!mounted) return;
    if (photo == null) {
      Navigator.of(context).pop();
      return;
    }
    await _analyze(photo);
  }

  // 함수이름: _analyze
  // 함수역할: 사진에서 알약을 찾고 첫 계획을 받는다.
  // 매개변수: photo (Uint8List): 찍은 사진.
  // 반환값: 완료 Future.
  Future<void> _analyze(Uint8List photo) async {
    setState(() {
      _photo = photo;
      _stage = _Stage.analyzing;
      _answers.clear();
      _crops.clear();
      _operationId = null;
    });
    unawaited(_readAspect(photo));
    try {
      final result = await _identify.requestMultiplePillIdentification(
        image: photo,
      );
      if (!_alive) return;
      if (result.observations.isEmpty) {
        _show(_Stage.problem, PhotoDoseProblem.noPills);
        return;
      }
      _observations = result.observations;
      _pills = [
        for (final o in result.observations)
          photoDosePillJson(o.index, o.identification),
      ];
      for (final o in result.observations) {
        try {
          _crops[o.index] = await _identify.cropPillImage(photo, o.boundingBox);
        } catch (_) {
          // 잘라 낸 사진이 없어도 기록에는 지장이 없다.
        }
      }
      await _flush;
      if (!_alive) return;
      await _replan(token: null);
    } catch (error) {
      if (_alive) _show(_Stage.problem, _problemFor(error));
    }
  }

  // 함수이름: _replan
  // 함수역할: 지금까지의 답으로 계획을 다시 받아 다음 단계를 정한다.
  // 매개변수: token (String?): 이전 계획 토큰.
  // 반환값: 완료 Future.
  Future<void> _replan({required String? token}) async {
    final plan = await _control.plan(
      pills: _pills,
      answers: _answerList,
      planToken: token,
    );
    if (!_alive) return;
    _plan = plan;
    final questions = [
      for (final q in plan.questions)
        if (!_answers.containsKey(q.index)) q,
    ];
    if (questions.isNotEmpty) {
      setState(() {
        _questions = questions;
        _questionIndex = 0;
        _stage = _Stage.question;
      });
      return;
    }
    if (!plan.hasWrite) {
      _show(_Stage.problem, PhotoDoseProblem.nothingToRecord);
      return;
    }
    setState(() {
      _operationId ??= MedicationHistoryControl.newOperationId();
      _confirmShownAt = DateTime.now();
      _stage = _Stage.confirm;
    });
  }

  // 함수이름: _answer
  // 함수역할: 질문 하나에 답하고, 질문이 끝나면 답을 모아 한 번에 다시 계산한다.
  // 매개변수: index: 알약 번호; medicationId: 고른 약(null은 기록하지 않음).
  // 반환값: 완료 Future.
  Future<void> _answer(int index, int? medicationId) async {
    if (_busy) return;
    _answers[index] = medicationId;
    if (_questionIndex + 1 < _questions.length) {
      setState(() => _questionIndex++);
      return;
    }
    setState(() => _busy = true);
    try {
      await _replan(token: _plan?.planToken);
    } catch (error) {
      if (_alive) _show(_Stage.problem, _problemFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 함수이름: _confirm
  // 함수역할: 확인 버튼. 겹치는 미전송 기록이 있으면 막고, 없으면 서버에 기록한 뒤 앱 상태를 갱신한다.
  // 매개변수: 없음. 반환값: 완료 Future.
  Future<void> _confirm() async {
    final plan = _plan;
    if (plan == null || _busy) return;
    // 바로 앞 질문의 버튼 자리와 겹치므로, 화면이 뜬 직후의 누름은 받지 않는다.
    if (DateTime.now().difference(_confirmShownAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    if (widget.hasPendingOverlap(plan)) {
      _show(_Stage.problem, PhotoDoseProblem.pendingQueue);
      return;
    }
    setState(() {
      _busy = true;
      _stage = _Stage.recording;
    });
    try {
      final result = await _control.confirm(
        pills: _pills,
        answers: _answerList,
        plan: plan,
        operationId: _operationId!,
      );
      if (!_alive) return;
      await widget.onRecorded(result);
      if (!_alive) return;
      setState(() {
        _result = result;
        _stage = _Stage.done;
      });
    } catch (error) {
      if (_alive) _show(_Stage.problem, _problemFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 함수이름: _retry
  // 함수역할: 문제 화면의 다시 시도. 기록 실패는 같은 작업 ID로 다시 보내고, 그 밖에는 사진부터 다시 한다.
  // 매개변수: 없음. 반환값: 완료 Future.
  Future<void> _retry() async {
    if (_problem == PhotoDoseProblem.connection &&
        _plan != null &&
        _operationId != null) {
      setState(() {
        _stage = _Stage.confirm;
        _confirmShownAt = DateTime.now();
      });
      return;
    }
    setState(() {
      _stage = _Stage.starting;
      _plan = null;
    });
    await _start();
  }

  bool get _alive => mounted && !_cancelled;

  List<PhotoDoseAnswer> get _answerList => [
    for (final entry in _answers.entries)
      PhotoDoseAnswer(entry.key, entry.value),
  ];

  void _show(_Stage stage, [PhotoDoseProblem? problem]) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _problem = problem;
    });
  }

  PhotoDoseProblem _problemFor(Object error) {
    if (error is ApiRequestException && error.statusCode == 409) {
      return PhotoDoseProblem.planChanged;
    }
    if (error is PillIdentificationException &&
        error.failure == PillIdentificationFailure.invalidPhoto) {
      return PhotoDoseProblem.noPills;
    }
    return PhotoDoseProblem.connection;
  }

  Future<void> _readAspect(Uint8List photo) async {
    try {
      final image = await decodeImageFromList(photo);
      if (mounted && image.height > 0) {
        setState(() => _photoAspect = image.width / image.height);
      }
      image.dispose();
    } catch (_) {}
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.recording,
      child: switch (_stage) {
        _Stage.starting => const _FlowScaffold(
          body: SizedBox.shrink(),
          showClose: false,
        ),
        _Stage.analyzing => _buildAnalyzing(),
        _Stage.question => _buildQuestion(),
        _Stage.confirm || _Stage.recording => _buildConfirm(),
        _Stage.done => _buildDone(),
        _Stage.problem => _buildProblem(),
      },
    );
  }

  Widget _buildAnalyzing() {
    return _FlowScaffold(
      key: const ValueKey('photoDoseAnalyzing'),
      onClose: _close,
      closeLabel: _text.stop,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          if (_photo != null)
            _PhotoFrame(photo: _photo!, aspect: _photoAspect, scanning: true),
          const SizedBox(height: 28),
          _Headline(_text.analyzingTitle),
          const SizedBox(height: 10),
          _Body(_text.aiNotice, muted: true),
        ],
      ),
      bottom: _WideButton.outlined(
        key: const ValueKey('photoDoseStop'),
        label: _text.stop,
        onPressed: _close,
      ),
    );
  }

  Widget _buildQuestion() {
    final plan = _plan!;
    final pill = _questions[_questionIndex];
    final options = [
      for (final id in pill.options)
        if (plan.medications[id] != null) plan.medications[id]!,
    ];
    final single = options.length == 1;
    final crop = _crops[pill.index];
    final step = _questions.length > 1
        ? _text.questionStep(_questionIndex + 1, _questions.length)
        : null;
    return _FlowScaffold(
      key: ValueKey('photoDoseQuestion${pill.index}'),
      onClose: _close,
      centerBody: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (step != null) ...[
            Text(
              step,
              style: const TextStyle(
                color: MedBuddyColors.primaryDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _Headline(single ? _text.isThisTitle : _text.whichTitle),
          const SizedBox(height: 20),
          if (single)
            _PhotoPair(
              crop: crop,
              imageUrl: options.single.imageUrl,
              takenLabel: _text.takenPhoto,
              registeredLabel: _text.registeredPhoto,
              index: pill.index,
            )
          else
            Center(
              child: _PillCrop(crop: crop, index: pill.index, size: 136),
            ),
          const SizedBox(height: 20),
          if (single) ...[
            KeepWordsText(
              _shortName(options.single.name),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            if (_ingredient(options.single.name).isNotEmpty)
              _Body(
                _ingredient(options.single.name),
                muted: true,
                center: true,
              ),
            const SizedBox(height: 6),
            _Body(_text.whenTaken(options.single), muted: true, center: true),
          ] else
            for (final option in options) ...[
              _OptionCard(
                key: ValueKey('photoDoseOption${option.id}'),
                medication: option,
                caption: _text.whenTaken(option),
                lookalike: pill.lookalikeIds.contains(option.id),
                lookalikeLabel: _text.sameLook,
                onTap: _busy ? null : () => _answer(pill.index, option.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
      bottom: single
          ? _ButtonPair(
              secondary: _WideButton.outlined(
                key: const ValueKey('photoDoseAnswerNo'),
                label: _text.no,
                onPressed: _busy ? null : () => _answer(pill.index, null),
              ),
              primary: _WideButton.filled(
                key: const ValueKey('photoDoseAnswerYes'),
                label: _text.yes,
                onPressed: _busy
                    ? null
                    : () => _answer(pill.index, options.single.id),
              ),
            )
          : _WideButton.outlined(
              key: const ValueKey('photoDoseAnswerUnknown'),
              label: _text.dontKnow,
              onPressed: _busy ? null : () => _answer(pill.index, null),
            ),
    );
  }

  Widget _buildConfirm() {
    final plan = _plan!;
    final recording = _stage == _Stage.recording;
    final matchedByMedication = <int, List<PhotoDosePill>>{};
    for (final pill in plan.pills) {
      if (pill.status == PhotoDosePillStatus.matched &&
          pill.medicationId != null) {
        matchedByMedication.putIfAbsent(pill.medicationId!, () => []).add(pill);
      }
    }
    final quiet = plan.pills
        .where(
          (p) =>
              p.status == PhotoDosePillStatus.skipped ||
              p.status == PhotoDosePillStatus.unknown,
        )
        .length;
    return _FlowScaffold(
      key: const ValueKey('photoDoseConfirm'),
      onClose: recording ? null : _close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_photo != null)
            _PhotoFrame(
              photo: _photo!,
              aspect: _photoAspect,
              observations: _observations,
              recordedIndexes: {
                for (final pills in matchedByMedication.values)
                  for (final p in pills) p.index,
              },
              maxHeight: 250,
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in plan.groups)
                _SlotChip(
                  slotKey: group.slotKey,
                  label: _text.slotName(group),
                  time: _text.clock(group.reminderAt),
                ),
              if (plan.asNeeded.isNotEmpty)
                _SlotChip(slotKey: 'as_needed', label: _text.asNeededLabel),
            ],
          ),
          const SizedBox(height: 14),
          _Headline(_text.confirmTitle(plan), large: true),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WarningBanner(
              lines: [
                for (final pill in plan.warnings) _text.warning(pill, plan),
              ],
            ),
          ],
          for (final group in plan.groups) ...[
            const SizedBox(height: 20),
            if (plan.groups.length > 1 || group.timing != 'on_time')
              _GroupHeader(
                slotKey: group.slotKey,
                title: _text.slotName(group),
                note: _text.timingNote(group),
              ),
            for (final id in group.medicationIds)
              _MedicationRow(
                medication: plan.medications[id]!,
                pills: matchedByMedication[id] ?? const [],
                crops: _crops,
                lookLabel: _text.foundByLook,
              ),
            if (group.missingMedicationIds.isNotEmpty)
              _InfoLine(
                icon: Icons.info_outline,
                text: _text.missing(group, plan),
              ),
          ],
          if (plan.asNeeded.isNotEmpty) ...[
            const SizedBox(height: 20),
            _GroupHeader(
              slotKey: 'as_needed',
              title: _text.asNeededLabel,
              note: _text.asNeededNote(plan.asNeeded),
            ),
            for (final entry in plan.asNeeded)
              _MedicationRow(
                medication: plan.medications[entry.medicationId]!,
                pills: matchedByMedication[entry.medicationId] ?? const [],
                crops: _crops,
                lookLabel: _text.foundByLook,
              ),
          ],
          if (quiet > 0)
            _InfoLine(
              icon: Icons.remove_circle_outline,
              text: _text.quiet(quiet),
            ),
          const SizedBox(height: 16),
          _Body(_text.aiResult, muted: true),
        ],
      ),
      bottom: _ButtonPair(
        secondary: _WideButton.cancel(
          key: const ValueKey('photoDoseCancel'),
          label: _text.cancel,
          semanticLabel: _text.cancelSemantic,
          onPressed: recording ? null : _close,
        ),
        primary: _WideButton.filled(
          key: const ValueKey('photoDoseConfirmButton'),
          label: recording ? _text.recording : _text.confirm,
          semanticLabel: _text.confirmSemantic,
          icon: Icons.check_rounded,
          busy: recording,
          onPressed: recording ? null : _confirm,
        ),
      ),
    );
  }

  Widget _buildDone() {
    final plan = _plan!;
    final result = _result!;
    final missing = [
      for (final group in plan.groups)
        if (group.missingMedicationIds.isNotEmpty) _text.missing(group, plan),
    ];
    return _FlowScaffold(
      key: const ValueKey('photoDoseDone'),
      showClose: false,
      body: Column(
        children: [
          const SizedBox(height: 36),
          const _CheckRing(size: 132),
          const SizedBox(height: 28),
          _Headline(_text.doneTitle, large: true, center: true),
          const SizedBox(height: 12),
          _Body(_text.doneSummary(plan), center: true),
          const SizedBox(height: 6),
          _Body(_text.takenAt(result.takenAt), muted: true, center: true),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final line in missing)
              _InfoLine(icon: Icons.info_outline, text: line),
          ],
        ],
      ),
      bottom: _WideButton.filled(
        key: const ValueKey('photoDoseHome'),
        label: _text.home,
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  Widget _buildProblem() {
    final problem = _problem ?? PhotoDoseProblem.connection;
    final plan = _plan;
    final register =
        problem == PhotoDoseProblem.noMedicines &&
        widget.onRegisterRequested != null;
    final retryable = problem != PhotoDoseProblem.noMedicines;
    return _FlowScaffold(
      key: ValueKey('photoDoseProblem${problem.name}'),
      onClose: _close,
      centerBody: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _ProblemBadge(problem: problem)),
          const SizedBox(height: 24),
          _Headline(_text.problemTitle(problem), center: true),
          const SizedBox(height: 10),
          _Body(_text.problemBody(problem), muted: true, center: true),
          if (problem == PhotoDoseProblem.nothingToRecord &&
              plan != null &&
              plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 20),
            _WarningBanner(
              lines: [
                for (final pill in plan.warnings) _text.warning(pill, plan),
              ],
            ),
          ],
        ],
      ),
      bottom: register
          ? _WideButton.filled(
              key: const ValueKey('photoDoseRegister'),
              label: _text.registerMedicine,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onRegisterRequested!();
              },
            )
          : retryable
          ? _ButtonPair(
              secondary: _WideButton.outlined(
                label: _text.close,
                onPressed: _close,
              ),
              primary: _WideButton.filled(
                key: const ValueKey('photoDoseRetry'),
                label:
                    problem == PhotoDoseProblem.connection &&
                        _operationId != null
                    ? _text.retry
                    : _text.retake,
                onPressed: _retry,
              ),
            )
          : _WideButton.outlined(label: _text.close, onPressed: _close),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 화면 조각

// 클래스명: _FlowScaffold
// 역할: 모든 단계가 쓰는 틀. 오른쪽 위 닫기, 스크롤 본문, 아래에 고정된 큰 버튼 영역.
class _FlowScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottom;
  final VoidCallback? onClose;
  final String? closeLabel;
  final bool showClose;
  final bool centerBody;

  const _FlowScaffold({
    super.key,
    required this.body,
    this.bottom,
    this.onClose,
    this.closeLabel,
    this.showClose = true,
    this.centerBody = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: showClose && onClose != null
                        ? IconButton(
                            key: const ValueKey('photoDoseClose'),
                            tooltip:
                                closeLabel ??
                                MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                            onPressed: onClose,
                            iconSize: 30,
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(56),
                              foregroundColor: MedBuddyColors.textBody,
                            ),
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: centerBody
                              ? math.max(0, constraints.maxHeight - 76)
                              : 0,
                        ),
                        child: centerBody ? Center(child: body) : body,
                      ),
                    ),
                  ),
                ),
                if (bottom != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      color: MedBuddyColors.pageBackground,
                      border: Border(
                        top: BorderSide(color: MedBuddyColors.divider),
                      ),
                    ),
                    child: bottom,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  final String text;
  final bool large;
  final bool center;

  const _Headline(this.text, {this.large = false, this.center = false});

  @override
  Widget build(BuildContext context) {
    return KeepWordsText(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: large ? 27 : 24,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  final bool muted;
  final bool center;

  const _Body(this.text, {this.muted = false, this.center = false});

  @override
  Widget build(BuildContext context) {
    return KeepWordsText(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: muted ? MedBuddyColors.textMuted : MedBuddyColors.textBody,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
    );
  }
}

// 클래스명: _PhotoFrame
// 역할: 찍은 사진. 분석 중에는 훑는 띠가, 확인 화면에서는 번호 상자가 겹친다.
class _PhotoFrame extends StatefulWidget {
  final Uint8List photo;
  final double aspect;
  final bool scanning;
  final List<MultiplePillObservation> observations;
  final Set<int> recordedIndexes;
  final double maxHeight;

  const _PhotoFrame({
    required this.photo,
    required this.aspect,
    this.scanning = false,
    this.observations = const [],
    this.recordedIndexes = const {},
    this.maxHeight = 320,
  });

  @override
  State<_PhotoFrame> createState() => _PhotoFrameState();
}

class _PhotoFrameState extends State<_PhotoFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (widget.scanning && !reduce) {
      if (!_scan.isAnimating) _scan.repeat();
    } else {
      _scan.stop();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: AspectRatio(
          aspectRatio: widget.aspect,
          child: ClipRRect(
            borderRadius: MedBuddyRadii.largeCard,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  widget.photo,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                if (widget.observations.isNotEmpty)
                  CustomPaint(
                    painter: _PillBoxPainter(
                      widget.observations,
                      widget.recordedIndexes,
                    ),
                  ),
                if (widget.scanning)
                  AnimatedBuilder(
                    animation: _scan,
                    builder: (context, _) =>
                        CustomPaint(painter: _ScanPainter(_scan.value)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double t;

  const _ScanPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    final y = size.height * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
    final band = Rect.fromLTWH(0, y - 36, size.width, 72);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MedBuddyColors.mint.withValues(alpha: 0),
            MedBuddyColors.mint.withValues(alpha: 0.55),
            MedBuddyColors.mint.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) => oldDelegate.t != t;
}

class _PillBoxPainter extends CustomPainter {
  final List<MultiplePillObservation> observations;
  final Set<int> recorded;

  const _PillBoxPainter(this.observations, this.recorded);

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in observations) {
      final box = o.boundingBox;
      final color = recorded.contains(o.index)
          ? MedBuddyColors.primary
          : const Color(0xFFB7791F);
      final rect = Rect.fromLTWH(
        box.left * size.width,
        box.top * size.height,
        box.width * size.width,
        box.height * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final radius = (size.shortestSide * 0.045).clamp(9.0, 14.0);
      final center = Offset(
        (rect.left - radius * 0.35).clamp(radius + 2, size.width - radius - 2),
        (rect.top - radius * 0.35).clamp(radius + 2, size.height - radius - 2),
      );
      canvas.drawCircle(center, radius + 2, Paint()..color = Colors.white);
      canvas.drawCircle(center, radius, Paint()..color = color);
      final label = TextPainter(
        text: TextSpan(
          text: '${o.index}',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PillBoxPainter oldDelegate) =>
      oldDelegate.observations != observations ||
      oldDelegate.recorded != recorded;
}

// 클래스명: _NumberBadge
// 역할: 사진의 번호 상자와 약 줄을 잇는 번호.
class _NumberBadge extends StatelessWidget {
  final int index;

  const _NumberBadge(this.index);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MedBuddyColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        '$index',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PillCrop extends StatelessWidget {
  final Uint8List? crop;
  final int index;
  final double size;

  const _PillCrop({required this.crop, required this.index, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: MedBuddyColors.surfaceSubtle,
                borderRadius: MedBuddyRadii.card,
                border: Border.all(color: MedBuddyColors.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: crop == null
                  ? const Icon(
                      Icons.medication_outlined,
                      color: MedBuddyColors.textLight,
                    )
                  : Image.memory(crop!, fit: BoxFit.cover),
            ),
          ),
          Positioned(left: 0, top: 0, child: _NumberBadge(index)),
        ],
      ),
    );
  }
}

// 클래스명: _PhotoPair
// 역할: "이 약이 맞나요?"의 찍은 약과 등록한 약 사진.
class _PhotoPair extends StatelessWidget {
  final Uint8List? crop;
  final String imageUrl;
  final String takenLabel;
  final String registeredLabel;
  final int index;

  const _PhotoPair({
    required this.crop,
    required this.imageUrl,
    required this.takenLabel,
    required this.registeredLabel,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    Widget labelled(Widget child, String label) => Column(
      children: [
        child,
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: MedBuddyColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelled(_PillCrop(crop: crop, index: index, size: 120), takenLabel),
        const Padding(
          padding: EdgeInsets.only(top: 52, left: 10, right: 10),
          child: Icon(
            Icons.compare_arrows_rounded,
            color: MedBuddyColors.textLight,
            size: 28,
          ),
        ),
        labelled(
          Padding(
            padding: const EdgeInsets.all(4),
            child: MedicationThumbnail(imageUrl: imageUrl, size: 120),
          ),
          registeredLabel,
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final PhotoDoseMedication medication;
  final String caption;
  final bool lookalike;
  final String lookalikeLabel;
  final VoidCallback? onTap;

  const _OptionCard({
    super.key,
    required this.medication,
    required this.caption,
    required this.lookalike,
    required this.lookalikeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MedBuddyColors.surface,
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: MedBuddyRadii.card,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(
              color: lookalike
                  ? MedBuddyColors.successBorder
                  : MedBuddyColors.cardBorder,
              width: lookalike ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              MedicationThumbnail(imageUrl: medication.imageUrl, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepWordsText(
                      _shortName(medication.name),
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lookalike ? '$caption · $lookalikeLabel' : caption,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MedBuddyColors.primary,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String slotKey;
  final String label;
  final String? time;

  const _SlotChip({required this.slotKey, required this.label, this.time});

  @override
  Widget build(BuildContext context) {
    final style = MedBuddySlotStyle.of(slotKey);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: MedBuddyRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.color, size: 22),
          const SizedBox(width: 7),
          Text(
            time == null ? label : '$label  $time',
            style: TextStyle(
              color: style.color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String slotKey;
  final String title;
  final String note;

  const _GroupHeader({
    required this.slotKey,
    required this.title,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final style = MedBuddySlotStyle.of(slotKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: style.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (note.isNotEmpty)
                  KeepWordsText(
                    note,
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _MedicationRow
// 역할: 기록할 약 한 줄. 찍은 알약(번호)과 등록한 약 사진을 나란히 놓는다.
class _MedicationRow extends StatelessWidget {
  final PhotoDoseMedication medication;
  final List<PhotoDosePill> pills;
  final Map<int, Uint8List> crops;
  final String lookLabel;

  const _MedicationRow({
    required this.medication,
    required this.pills,
    required this.crops,
    required this.lookLabel,
  });

  @override
  Widget build(BuildContext context) {
    final byLook = pills.any((p) => p.foundByLook);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.cardBorder),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Row(
        children: [
          for (final pill in pills.take(2))
            _PillCrop(crop: crops[pill.index], index: pill.index, size: 58),
          const SizedBox(width: 4),
          MedicationThumbnail(imageUrl: medication.imageUrl, size: 58),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(
                  _shortName(medication.name),
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                if (_ingredient(medication.name).isNotEmpty)
                  KeepWordsText(
                    _ingredient(medication.name),
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                if (medication.dosage.isNotEmpty || byLook) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (medication.dosage.isNotEmpty) medication.dosage,
                      if (byLook) lookLabel,
                    ].join(' · '),
                    style: TextStyle(
                      color: byLook
                          ? MedBuddyColors.reminderAccent
                          : MedBuddyColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final List<String> lines;

  const _WarningBanner({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('photoDoseWarnings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MedBuddyColors.warningSurface,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.warningBorder, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: MedBuddyColors.reminderAccent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: KeepWordsText(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF5C3D00),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: MedBuddyColors.textSubtle, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeepWordsText(
              text,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemBadge extends StatelessWidget {
  final PhotoDoseProblem problem;

  const _ProblemBadge({required this.problem});

  @override
  Widget build(BuildContext context) {
    final (icon, color, tint) = switch (problem) {
      PhotoDoseProblem.noMedicines => (
        Icons.medication_outlined,
        MedBuddyColors.primary,
        MedBuddyColors.mint,
      ),
      PhotoDoseProblem.nothingToRecord => (
        Icons.front_hand_outlined,
        MedBuddyColors.reminderAccent,
        MedBuddyColors.butterSurface,
      ),
      PhotoDoseProblem.noPills => (
        Icons.center_focus_weak_rounded,
        MedBuddyColors.infoBlue,
        MedBuddyColors.lavenderSurface,
      ),
      _ => (
        Icons.sync_problem_rounded,
        MedBuddyColors.danger,
        MedBuddyColors.dangerSurface,
      ),
    };
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 52),
    );
  }
}

// 클래스명: _CheckRing
// 역할: 완료 화면의 체크 표시. 원과 체크가 한 번 그려지며, 움직임 줄이기 설정에서는 정지 상태다.
class _CheckRing extends StatefulWidget {
  final double size;

  const _CheckRing({required this.size});

  @override
  State<_CheckRing> createState() => _CheckRingState();
}

class _CheckRingState extends State<_CheckRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _draw.value = 1;
    } else if (_draw.value == 0 && !_draw.isAnimating) {
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      child: AnimatedBuilder(
        animation: _draw,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _CheckRingPainter(
            Curves.easeOutCubic.transform(_draw.value),
          ),
        ),
      ),
    );
  }
}

class _CheckRingPainter extends CustomPainter {
  final double t;

  const _CheckRingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final fill = (t / 0.55).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      radius * (0.86 + 0.14 * fill),
      Paint()..color = MedBuddyColors.mint.withValues(alpha: fill),
    );
    final ring = Paint()
      ..color = MedBuddyColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fill,
      false,
      ring,
    );
    final check = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
    if (check <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.72, size.height * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * check),
      Paint()
        ..color = MedBuddyColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckRingPainter oldDelegate) =>
      oldDelegate.t != t;
}

// 클래스명: _ButtonPair
// 역할: 아래쪽 두 버튼. 확인 같은 주 버튼이 오른쪽, 큰 글씨에서는 주 버튼이 위로 간다.
class _ButtonPair extends StatelessWidget {
  final Widget secondary;
  final Widget primary;

  const _ButtonPair({required this.secondary, required this.primary});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale > 1.25) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [primary, const SizedBox(height: 12), secondary],
      );
    }
    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 16),
        Expanded(child: primary),
      ],
    );
  }
}

// 클래스명: _WideButton
// 역할: 높이 64dp의 큰 버튼. 초록 채움(주 행동), 테두리(보조), 빨간 테두리(취소) 세 가지다.
class _WideButton extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color background;
  final Color foreground;
  final Color border;

  const _WideButton._({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.border,
    this.semanticLabel,
    this.icon,
    this.busy = false,
  });

  const _WideButton.filled({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    String? semanticLabel,
    IconData? icon,
    bool busy = false,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         semanticLabel: semanticLabel,
         icon: icon,
         busy: busy,
         background: MedBuddyColors.primary,
         foreground: Colors.white,
         border: MedBuddyColors.primary,
       );

  const _WideButton.outlined({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         background: MedBuddyColors.surface,
         foreground: MedBuddyColors.primaryDark,
         border: MedBuddyColors.outline,
       );

  const _WideButton.cancel({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    String? semanticLabel,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         semanticLabel: semanticLabel,
         icon: Icons.close_rounded,
         background: MedBuddyColors.surface,
         foreground: MedBuddyColors.danger,
         border: MedBuddyColors.danger,
       );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: enabled || busy ? background : MedBuddyColors.surfaceSubtle,
          borderRadius: MedBuddyRadii.card,
          child: InkWell(
            onTap: onPressed,
            borderRadius: MedBuddyRadii.card,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: MedBuddyRadii.card,
                border: Border.all(
                  color: enabled || busy ? border : MedBuddyColors.outline,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: foreground,
                      ),
                    )
                  else if (icon != null)
                    Icon(
                      icon,
                      color: enabled ? foreground : MedBuddyColors.textLight,
                      size: 26,
                    ),
                  if (busy || icon != null) const SizedBox(width: 8),
                  Flexible(
                    child: KeepWordsText(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: enabled || busy
                            ? foreground
                            : MedBuddyColors.textLight,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 문구

// 클래스명: _PhotoDoseText
// 역할: 사진으로 복용 기록 화면의 한국어·영어 문구.
class _PhotoDoseText {
  final bool isEnglish;

  const _PhotoDoseText(this.isEnglish);

  String get stop => isEnglish ? 'Stop' : '그만하기';
  String get analyzingTitle =>
      isEnglish ? 'Checking your pills' : '약을 확인하고 있어요';
  String get aiNotice => isEnglish
      ? 'The photo is analysed by an external AI (Google Gemini, or Anthropic Claude when Gemini fails) and is not stored.'
      : '사진은 약을 확인하려고 외부 AI(Google Gemini, 장애 시 Anthropic Claude)로 분석되며 저장하지 않아요.';
  String get aiResult => isEnglish
      ? 'These are AI results. Check that each photo matches the medicine.'
      : 'AI가 찾은 결과예요. 사진과 약이 같은지 확인해 주세요.';
  String get isThisTitle => isEnglish ? 'Is this the medicine?' : '이 약이 맞나요?';
  String get whichTitle => isEnglish ? 'Which medicine is this?' : '어떤 약인가요?';
  String questionStep(int current, int total) =>
      isEnglish ? 'Pill $current of $total' : '알약 $total개 중 $current번째';
  String get takenPhoto => isEnglish ? 'Your photo' : '찍은 약';
  String get registeredPhoto => isEnglish ? 'Registered' : '등록한 약';
  String get sameLook => isEnglish ? 'same look' : '모양·색이 같아요';
  String get foundByLook =>
      isEnglish ? 'Found by shape and colour' : '모양·색으로 찾았어요';
  String get yes => isEnglish ? 'Yes' : '네, 맞아요';
  String get no => isEnglish ? 'No' : '아니에요';
  String get dontKnow => isEnglish ? "I don't know" : '모르겠어요';
  String get confirm => isEnglish ? 'Confirm' : '확인';
  String get confirmSemantic => isEnglish ? 'Record these doses' : '기록하기';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get cancelSemantic =>
      isEnglish ? 'Close without recording' : '기록하지 않고 닫기';
  String get recording => isEnglish ? 'Recording' : '기록하는 중';
  String get doneTitle => isEnglish ? 'Dose recorded' : '복약을 완료했어요';
  String get home => isEnglish ? 'Back to home' : '홈으로';
  String get asNeededLabel => isEnglish ? 'As needed' : '필요할 때';
  String get retake => isEnglish ? 'Take the photo again' : '다시 찍기';
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  String get close => isEnglish ? 'Close' : '닫기';
  String get registerMedicine => isEnglish ? 'Add a medicine' : '약 등록하기';

  String slot(String key) => medicationSlotLabel(key, isEnglish: isEnglish);

  String slotName(PhotoDoseGroup group) => group.isOvernight
      ? (isEnglish
            ? "Yesterday's ${slot(group.slotKey).toLowerCase()}"
            : '어제 ${slot(group.slotKey)}')
      : slot(group.slotKey);

  String clock(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return isEnglish
        ? '$h12:$minute ${hour < 12 ? 'AM' : 'PM'}'
        : '${hour < 12 ? '오전' : '오후'} $h12:$minute';
  }

  String whenTaken(PhotoDoseMedication medication) {
    if (medication.isAsNeeded) {
      return isEnglish ? 'Taken as needed' : '필요할 때 드시는 약';
    }
    final slots = medication.slotKeys.map(slot).join(isEnglish ? ', ' : ' · ');
    return isEnglish ? 'Taken at: $slots' : '$slots에 드시는 약';
  }

  String confirmTitle(PhotoDosePlan plan) {
    final groups = plan.groups;
    if (groups.length == 1 && plan.asNeeded.isEmpty) {
      return isEnglish
          ? 'Are you taking your ${slotName(groups.single).toLowerCase()} medicine?'
          : '${slotName(groups.single)} 약을 드시는 게 맞나요?';
    }
    if (groups.isEmpty) {
      return isEnglish ? 'Are you taking this now?' : '지금 드시는 약이 맞나요?';
    }
    final parts = [
      for (final g in groups)
        isEnglish
            ? '${g.medicationIds.length} ${slotName(g).toLowerCase()}'
            : '${slotName(g)} 약 ${g.medicationIds.length}개',
      if (plan.asNeeded.isNotEmpty)
        isEnglish
            ? '${plan.asNeeded.length} as-needed'
            : '필요할 때 드시는 약 ${plan.asNeeded.length}개',
    ];
    return isEnglish
        ? 'Are you taking ${parts.join(' and ')} medicines together now?'
        : '${_joinKorean(parts)}를 지금 함께 드시는 게 맞나요?';
  }

  String timingNote(PhotoDoseGroup group) {
    final time = clock(group.reminderAt);
    return switch (group.timing) {
      'early' =>
        isEnglish
            ? 'A little before the $time reminder'
            : '$time 알림보다 조금 일찍이에요',
      'late' => isEnglish ? 'The $time reminder has passed' : '$time 알림이 지났어요',
      'overnight' =>
        isEnglish ? "Recorded for yesterday's dose" : '어제 약으로 기록해요',
      _ => isEnglish ? 'Reminder at $time' : '$time 알림',
    };
  }

  String asNeededNote(List<PhotoDoseAsNeeded> entries) {
    final counts = entries.where((e) => e.takenToday > 0).toList();
    if (counts.isEmpty) {
      return isEnglish ? 'Recorded once for now' : '지금 시각으로 1회 기록해요';
    }
    final next = counts.first.takenToday + 1;
    return isEnglish ? 'This is dose $next today' : '오늘 $next번째예요';
  }

  String warning(PhotoDosePill pill, PhotoDosePlan plan) {
    final name = _shortName(plan.medications[pill.medicationId]?.name ?? '');
    final at = pill.detailAt;
    final time = at == null ? '' : clock(at);
    if (isEnglish) {
      return switch (pill.status) {
        PhotoDosePillStatus.recentlyTaken =>
          '$name was already taken at $time.',
        PhotoDosePillStatus.alreadyTaken => '$name has been taken for today.',
        PhotoDosePillStatus.tooEarly =>
          '$name is due at $time. It is not time yet.',
        PhotoDosePillStatus.unclearSlot =>
          "It's unclear which dose $name is. Record it in the schedule.",
        PhotoDosePillStatus.extra =>
          'More $name than one dose is in the photo.',
        PhotoDosePillStatus.notDue => '$name is not taken today.',
        _ => '',
      };
    }
    return switch (pill.status) {
      PhotoDosePillStatus.recentlyTaken =>
        '$name${_josa(name, '은', '는')} $time에 이미 드셨어요.',
      PhotoDosePillStatus.alreadyTaken =>
        '$name${_josa(name, '은', '는')} 오늘 이미 다 드셨어요.',
      PhotoDosePillStatus.tooEarly =>
        '$name${_josa(name, '은', '는')} $time 약이에요. 아직 드실 때가 아니에요.',
      PhotoDosePillStatus.unclearSlot =>
        '$name${_josa(name, '은', '는')} 언제 드실 약인지 알 수 없어요. 일정에서 직접 기록해 주세요.',
      PhotoDosePillStatus.extra =>
        '$name${_josa(name, '이', '가')} 정해진 양보다 많이 찍혔어요.',
      PhotoDosePillStatus.notDue =>
        '$name${_josa(name, '은', '는')} 오늘 드시는 날이 아니에요.',
      _ => '',
    };
  }

  String missing(PhotoDoseGroup group, PhotoDosePlan plan) {
    final names = [
      for (final id in group.missingMedicationIds)
        _shortName(plan.medications[id]?.name ?? ''),
    ].where((n) => n.isNotEmpty).join(', ');
    return isEnglish
        ? 'Not in the photo yet (${slotName(group).toLowerCase()}): $names'
        : '아직 안 찍힌 ${slotName(group)} 약: $names';
  }

  String quiet(int count) => isEnglish
      ? '$count pill(s) are not your medicines and will not be recorded.'
      : '복약 중인 약이 아닌 알약 $count개는 기록하지 않아요.';

  String doneSummary(PhotoDosePlan plan) {
    final parts = [
      for (final g in plan.groups)
        isEnglish
            ? '${g.medicationIds.length} ${slotName(g).toLowerCase()}'
            : '${slotName(g)} 약 ${g.medicationIds.length}개',
      if (plan.asNeeded.isNotEmpty)
        isEnglish
            ? '${plan.asNeeded.length} as-needed'
            : '필요할 때 드시는 약 ${plan.asNeeded.length}개',
    ];
    return isEnglish
        ? 'Recorded ${parts.join(' and ')} medicine(s)'
        : '${_joinKorean(parts)}를 기록했어요';
  }

  String takenAt(DateTime time) =>
      isEnglish ? 'Taken at ${clock(time)}' : '${clock(time)}에 드셨어요';

  String problemTitle(PhotoDoseProblem problem) => switch (problem) {
    PhotoDoseProblem.noMedicines =>
      isEnglish ? 'No medicines to record yet' : '기록할 약이 아직 없어요',
    PhotoDoseProblem.noPills =>
      isEnglish ? "We couldn't see any pills" : '알약이 잘 보이지 않아요',
    PhotoDoseProblem.nothingToRecord =>
      isEnglish ? 'Nothing to record now' : '지금 기록할 약이 없어요',
    PhotoDoseProblem.pendingQueue =>
      isEnglish ? 'An earlier record is not sent yet' : '먼저 보내지 못한 기록이 있어요',
    PhotoDoseProblem.planChanged =>
      isEnglish ? 'Your schedule changed' : '그사이 기록이 바뀌었어요',
    PhotoDoseProblem.connection => isEnglish ? "Couldn't connect" : '연결하지 못했어요',
  };

  String problemBody(PhotoDoseProblem problem) => switch (problem) {
    PhotoDoseProblem.noMedicines =>
      isEnglish
          ? 'Add your medicines first. Then a photo of the pills in your hand records the dose.'
          : '먼저 드시는 약을 등록해 주세요. 그다음부터는 손에 든 약을 찍으면 복용이 기록돼요.',
    PhotoDoseProblem.noPills =>
      isEnglish
          ? 'Spread the pills on your palm, away from each other, and take the photo again in good light.'
          : '알약을 손바닥 위에 서로 떨어지게 올리고, 밝은 곳에서 다시 찍어 주세요.',
    PhotoDoseProblem.nothingToRecord =>
      isEnglish
          ? 'None of the pills in the photo can be recorded now.'
          : '사진 속 약 가운데 지금 기록할 약이 없어요.',
    PhotoDoseProblem.pendingQueue =>
      isEnglish
          ? 'Connect to the internet and wait a moment so the earlier record is sent, then try again.'
          : '인터넷에 연결된 상태에서 잠시 기다리면 이전 기록이 전송돼요. 그다음 다시 찍어 주세요.',
    PhotoDoseProblem.planChanged =>
      isEnglish
          ? 'Another record was saved meanwhile, or more than 15 minutes passed. Take the photo again.'
          : '다른 곳에서 기록했거나 사진을 찍은 지 15분이 지났어요. 사진을 다시 찍어 주세요.',
    PhotoDoseProblem.connection =>
      isEnglish
          ? 'Check the internet connection and try again. Nothing was recorded.'
          : '인터넷 연결을 확인하고 다시 시도해 주세요. 아직 아무것도 기록하지 않았어요.',
  };
}

// 함수이름: _shortName
// 함수역할: 문장 안에서 읽기 쉽게 괄호 속 성분명을 뺀 약 이름을 만든다.
// 매개변수: name: 약 이름. 반환값: 짧은 이름.
String _shortName(String name) {
  final open = name.indexOf('(');
  final short = (open > 0 ? name.substring(0, open) : name).trim();
  return short.isEmpty ? name : short;
}

// 함수이름: _ingredient
// 함수역할: 약 이름의 괄호 속 성분명을 꺼낸다.
// 매개변수: name: 약 이름. 반환값: 성분명 또는 빈 문자열.
String _ingredient(String name) {
  final match = RegExp(r'\(([^()]+)\)\s*$').firstMatch(name);
  return match?.group(1)?.trim() ?? '';
}

// 함수이름: _josa
// 함수역할: 앞 글자의 받침에 맞는 조사를 고른다.
// 매개변수: word: 앞말; withFinal: 받침이 있을 때; withoutFinal: 없을 때. 반환값: 조사.
String _josa(String word, String withFinal, String withoutFinal) {
  if (word.isEmpty) return withoutFinal;
  final code = word.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) {
    return RegExp(r'[0-9lmnLMN]$').hasMatch(word) ? withFinal : withoutFinal;
  }
  return (code - 0xAC00) % 28 == 0 ? withoutFinal : withFinal;
}

// 함수이름: _joinKorean
// 함수역할: "A와 B", "A, B와 C"처럼 묶는다. 마지막 앞말의 받침에 맞춰 와/과를 고른다.
// 매개변수: parts: 항목. 반환값: 묶은 문구.
String _joinKorean(List<String> parts) {
  if (parts.length < 2) return parts.join();
  final head = parts.sublist(0, parts.length - 1);
  final last = head.last;
  return '${head.sublist(0, head.length - 1).map((p) => '$p, ').join()}$last${_josa(last, '과', '와')} ${parts.last}';
}
