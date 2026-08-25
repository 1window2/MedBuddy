// 파일명: link_patient_caregiver_ui_boundary.dart
// 역할: 환자 코드 생성, 보호자 등록과 연동 목록 관리 화면을 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_caregiver_patient_local_state_control.dart';
import '../controls/manage_linked_chat_control.dart';
import '../entities/chat_message_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../services/user_facing_error_message.dart';
import 'check_caregiver_medication_ui_boundary.dart';
import 'linked_chat_ui_boundary.dart';

typedef LinkPatientCaregiverFactory =
    LinkPatientCaregiver Function(String userHash);
typedef LinkedChatControlFactory = ManageLinkedChat Function(String userHash);

// 파일명: link_patient_caregiver_ui_boundary.dart
// 역할: 환자와 보호자 연동을 관리하는 화면을 구성한다.

// 클래스명: LinkPatientCaregiverUI
// 역할: 환자 코드 생성, 보호자 코드 등록, 연동 목록 조회/해제를 한 화면에서 처리한다.
// 주요 책임:
// - 현재 사용자 해시 기준 연동 목록을 조회한다.
// - 환자용 임시 코드를 생성해 보호자에게 전달할 수 있게 한다.
// - 보호자가 환자 코드를 입력해 연동을 등록할 수 있게 한다.
class LinkPatientCaregiverUI extends StatefulWidget {
  final String initialUserHash;
  final bool chatLabEnabled;
  final UserSetting userSetting;
  final LinkPatientCaregiverFactory? controlFactory;
  final LinkedChatControlFactory? chatControlFactory;

  const LinkPatientCaregiverUI({
    super.key,
    this.initialUserHash = PatientHash.defaultPatientHash,
    this.chatLabEnabled = false,
    this.userSetting = const UserSetting(),
    this.controlFactory,
    this.chatControlFactory,
  });

  @override
  State<LinkPatientCaregiverUI> createState() => _LinkPatientCaregiverUIState();
}

class _LinkPatientCaregiverUIState extends State<LinkPatientCaregiverUI> {
  static const ManageCaregiverPatientLocalState _localStateControl =
      ManageCaregiverPatientLocalState();
  late final TextEditingController _patientCodeController;
  late String _committedUserHash;
  late LinkPatientCaregiver _control;
  late ManageLinkedChat _chatControl;

  List<PatientCaregiverLink> _links = const [];
  Map<String, String> _patientLabels = const {};
  Map<int, List<ChatMedicationContext>> _medicationContextsByLink = const {};
  late String _statusMessage;
  bool _isLoading = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _statusMessage = _text.loadingLinks;
    _patientCodeController = TextEditingController();
    _committedUserHash = PatientHash.normalizePatientHash(
      widget.initialUserHash,
    );
    _control = _createControl(_committedUserHash);
    _chatControl = _createChatControl(_committedUserHash);
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant LinkPatientCaregiverUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUserHash = PatientHash.normalizePatientHash(
      widget.initialUserHash,
    );
    final userChanged = nextUserHash != _committedUserHash;
    final chatSettingChanged =
        widget.chatLabEnabled != oldWidget.chatLabEnabled;
    final languageChanged =
        widget.userSetting.language != oldWidget.userSetting.language;
    if (!userChanged && !chatSettingChanged && !languageChanged) {
      return;
    }
    if (userChanged) {
      _replaceControl(nextUserHash);
    }
    _links = const [];
    _patientLabels = const {};
    _medicationContextsByLink = const {};
    _statusMessage = _text.loadingLinks;
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _control.dispose();
    _chatControl.dispose();
    _patientCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textScale = mediaQuery.textScaler.scale(16) / 16;
    final usesScrollableLayout =
        mediaQuery.size.height < 700 || textScale > 1.3;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: usesScrollableLayout
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: _buildLinkContent(usesScrollableList: true),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(42, 24, 42, 28),
                child: _buildLinkContent(usesScrollableList: false),
              ),
      ),
    );
  }

  // 함수이름: _buildLinkContent
  // 함수역할:
  // - 일반 화면에서는 연동 목록이 남은 공간을 채우게 배치한다.
  // - 작은 화면이나 큰 글씨에서는 전체 내용을 한 번에 스크롤할 수 있게 배치한다.
  // 매개변수:
  // - usesScrollableList: 연동 목록을 화면 전체 스크롤 안에 포함할지 여부
  // 반환값:
  // - 현재 화면 크기에 맞게 구성한 환자·보호자 연동 화면 내용
  Widget _buildLinkContent({required bool usesScrollableList}) {
    final text = _text;
    final linkList = _LinkListCard(
      links: _links,
      currentUserHash: _committedUserHash,
      isEnabled: !_isLoading,
      shrinkWrap: usesScrollableList,
      patientLabels: _patientLabels,
      showChatAction: widget.chatLabEnabled,
      medicationContextsByLink: _medicationContextsByLink,
      onChatRequested: _openLinkedChat,
      onPatientMedicationRequested: _openPatientMedicationInfo,
      onPatientLabelRequested: _showPatientLabelDialog,
      onUnlinkRequested: _removePatientCaregiverLink,
      text: text,
    );
    final footer = _LinkActionFooter(
      onGeneratePatientCodeRequested: _isLoading ? null : _generatePatientHash,
      onRegisterPatientRequested: _isLoading
          ? null
          : _showRegisterPatientDialog,
      text: text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: text.close,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.close,
            color: MedBuddyColors.textMuted,
            size: 30,
          ),
        ),
        SizedBox(height: usesScrollableList ? 20 : 30),
        Text(
          text.screenTitle,
          style: const TextStyle(
            color: Color(0xFF0A0A0A),
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: usesScrollableList ? 18 : 26),
        _StatusCard(statusMessage: _statusMessage, isLoading: _isLoading),
        SizedBox(height: usesScrollableList ? 18 : 24),
        if (usesScrollableList) linkList else Expanded(child: linkList),
        const SizedBox(height: 20),
        footer,
      ],
    );
  }

  _LinkPatientCaregiverText get _text =>
      _LinkPatientCaregiverText(widget.userSetting.language);

  Future<void> _refreshLinks() async {
    await _runLinkAction((request) async {
      final links = await request.control.requestLinkScreen();
      if (!_isCurrentRequest(request)) {
        return;
      }
      final labels = await _loadPatientLabels(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      final medicationContexts = await _loadChatMedicationContexts(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      setState(() {
        _links = links;
        _patientLabels = labels;
        _medicationContextsByLink = medicationContexts;
        _statusMessage = links.isEmpty
            ? _text.noSavedLinks
            : _text.linkCount(links.length);
      });
    });
  }

  Future<void> _generatePatientHash() async {
    PatientLinkCode? patientCode;
    final request = await _runLinkAction((request) async {
      final generatedCode = await request.control.generatePatientHash();
      if (!_isCurrentRequest(request)) {
        return;
      }
      patientCode = generatedCode;
      setState(() {
        _statusMessage = _text.codeGenerated;
      });
    });

    if (request == null || patientCode == null || !_isCurrentRequest(request)) {
      return;
    }

    await _showPatientCodeDialog(patientCode!);
    if (_isCurrentRequest(request)) {
      await _refreshLinks();
    }
  }

  Future<bool> _requestPatientCaregiverLink() async {
    if (_isLoading || !mounted) {
      return false;
    }

    final patientCode = _patientCodeController.text.trim();
    if (patientCode.isEmpty) {
      setState(() {
        _statusMessage = _text.enterPatientCode;
      });
      return false;
    }

    var registered = false;
    final request = await _runLinkAction((request) async {
      await request.control.requestPatientCaregiverLink(patientCode);
      if (!_isCurrentRequest(request)) {
        return;
      }
      final links = await request.control.requestLinkScreen();
      if (!_isCurrentRequest(request)) {
        return;
      }
      final labels = await _loadPatientLabels(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      final medicationContexts = await _loadChatMedicationContexts(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      setState(() {
        _links = links;
        _patientLabels = labels;
        _medicationContextsByLink = medicationContexts;
        _patientCodeController.clear();
        _statusMessage = _text.linkRegistered;
        registered = true;
      });
    });
    return request != null && registered;
  }

  Future<void> _removePatientCaregiverLink(PatientCaregiverLink link) async {
    if (_isLoading || !mounted) {
      return;
    }

    final linkId = link.linkId;
    if (linkId == null) {
      setState(() {
        _statusMessage = _text.missingLinkId;
      });
      return;
    }

    await _runLinkAction((request) async {
      await request.control.requestUnlink(linkId);
      if (!_isCurrentRequest(request)) {
        return;
      }
      await _localStateControl.clearPatientState(
        caregiverHash: link.caregiverHash,
        patientHash: link.patientHash,
      );
      final links = await request.control.requestLinkScreen();
      if (!_isCurrentRequest(request)) {
        return;
      }
      final labels = await _loadPatientLabels(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      final medicationContexts = await _loadChatMedicationContexts(links);
      if (!_isCurrentRequest(request)) {
        return;
      }
      setState(() {
        _links = links;
        _patientLabels = labels;
        _medicationContextsByLink = medicationContexts;
        _statusMessage = _text.linkRemoved;
      });
    });
  }

  // 함수이름: _loadPatientLabels
  // 함수역할:
  // - 현재 보호자가 연결한 환자별 표시 이름을 로컬 저장소에서 읽는다.
  // 매개변수:
  // - links: 서버가 반환한 현재 연동 목록
  // 반환값:
  // - 환자 hash를 키로 사용하는 표시 이름 Map
  Future<Map<String, String>> _loadPatientLabels(
    List<PatientCaregiverLink> links,
  ) async {
    return _localStateControl.loadLabels(
      caregiverHash: _committedUserHash,
      links: links,
    );
  }

  // 함수이름: _loadChatMedicationContexts
  // 함수역할:
  // - 실험 기능이 켜졌을 때 각 연동 환자의 활성 복약 목록을 병렬로 불러온다.
  // - 한 연동의 조회 실패가 다른 환자의 연동 목록까지 막지 않게 빈 목록으로 격리한다.
  Future<Map<int, List<ChatMedicationContext>>> _loadChatMedicationContexts(
    List<PatientCaregiverLink> links,
  ) async {
    if (!widget.chatLabEnabled) {
      return const {};
    }
    final entries = await Future.wait(
      links.map((link) async {
        final linkId = link.linkId;
        if (linkId == null || !link.linkStatus) {
          return null;
        }
        try {
          final medications = await _chatControl.requestMedicationContexts(
            linkId: linkId,
          );
          return MapEntry(linkId, medications);
        } catch (_) {
          return MapEntry<int, List<ChatMedicationContext>>(linkId, const []);
        }
      }),
    );
    return Map<int, List<ChatMedicationContext>>.fromEntries(
      entries.whereType<MapEntry<int, List<ChatMedicationContext>>>(),
    );
  }

  Future<_LinkRequest?> _runLinkAction(
    Future<void> Function(_LinkRequest request) action,
  ) async {
    if (!mounted || _isLoading) {
      return null;
    }

    final request = _LinkRequest(
      generation: ++_requestGeneration,
      userHash: _committedUserHash,
      control: _control,
    );
    setState(() {
      _isLoading = true;
    });

    try {
      await action(request);
      return _isCurrentRequest(request) ? request : null;
    } catch (error) {
      if (_isCurrentRequest(request)) {
        setState(() {
          _statusMessage = UserFacingErrorMessage.resolve(
            error,
            isEnglish: _text.isEnglish,
          );
        });
      }
      return null;
    } finally {
      if (_isCurrentRequest(request)) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _scheduleRefresh() {
    final generation = _requestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      _refreshLinks();
    });
  }

  void _replaceControl(String userHash) {
    final previousControl = _control;
    final previousChatControl = _chatControl;
    final nextControl = _createControl(userHash);
    final nextChatControl = _createChatControl(userHash);
    _requestGeneration += 1;
    _committedUserHash = userHash;
    _control = nextControl;
    _chatControl = nextChatControl;
    _isLoading = false;
    previousControl.dispose();
    previousChatControl.dispose();
  }

  LinkPatientCaregiver _createControl(String userHash) {
    return widget.controlFactory?.call(userHash) ??
        LinkPatientCaregiver(userHash: userHash);
  }

  ManageLinkedChat _createChatControl(String userHash) {
    return widget.chatControlFactory?.call(userHash) ??
        ManageLinkedChat(userHash: userHash);
  }

  bool _isCurrentRequest(_LinkRequest request) {
    return mounted &&
        request.generation == _requestGeneration &&
        request.userHash == _committedUserHash &&
        identical(request.control, _control);
  }

  // 함수이름: _showPatientLabelDialog
  // 함수역할:
  // - 보호자가 여러 환자를 쉽게 구분하도록 환자별 표시 이름을 입력받아 저장한다.
  // 매개변수:
  // - link: 별칭을 변경할 환자·보호자 연동 정보
  // 반환값:
  // - 없음
  Future<void> _showPatientLabelDialog(PatientCaregiverLink link) async {
    if (link.caregiverHash != _committedUserHash || !mounted) {
      return;
    }
    var draftLabel =
        _patientLabels[link.patientHash] ??
        _localStateControl.fallbackLabel(link.patientHash);
    final submittedLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_text.patientLabelTitle),
          content: TextFormField(
            initialValue: draftLabel,
            autofocus: true,
            maxLength: ManageCaregiverPatientLocalState.maximumLabelLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: _text.patientLabelHint,
              helperText: _text.patientLabelHelper,
            ),
            onChanged: (value) => draftLabel = value,
            onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_text.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draftLabel),
              child: Text(_text.save),
            ),
          ],
        );
      },
    );
    if (submittedLabel == null || !mounted) {
      return;
    }
    final linkId = link.linkId;
    if (linkId == null) {
      setState(() {
        _statusMessage = _text.missingAliasLinkId;
      });
      return;
    }
    String? savedLabel;
    final request = await _runLinkAction((request) async {
      final updatedLink = await request.control.savePatientAlias(
        linkId: linkId,
        patientAlias: submittedLabel,
      );
      if (!_isCurrentRequest(request)) {
        return;
      }
      savedLabel = await _localStateControl.saveLabel(
        caregiverHash: link.caregiverHash,
        patientHash: link.patientHash,
        label: updatedLink.patientAlias ?? submittedLabel,
      );
      if (!_isCurrentRequest(request)) {
        return;
      }
      setState(() {
        _links = _links
            .map(
              (currentLink) =>
                  currentLink.linkId == linkId ? updatedLink : currentLink,
            )
            .toList(growable: false);
        _patientLabels = {..._patientLabels, link.patientHash: savedLabel!};
      });
    });
    final confirmedLabel = savedLabel;
    if (request == null || confirmedLabel == null || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_text.patientLabelSaved(confirmedLabel)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _openPatientMedicationInfo(PatientCaregiverLink link) {
    if (_isLoading) {
      return;
    }

    final caregiverHash = _committedUserHash;
    if (!link.linkStatus ||
        link.caregiverHash != caregiverHash ||
        link.patientHash.trim().isEmpty) {
      setState(() {
        _statusMessage = _text.linkedPatientOnly;
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CheckCaregiverMedicationUI(
          caregiverHash: caregiverHash,
          patientHash: link.patientHash,
          patientLabel: _patientLabels[link.patientHash],
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  // 함수명: _openLinkedChat
  // 역할:
  // - 현재 사용자가 참여한 연동의 실시간 가족 채팅 화면을 연다.
  void _openLinkedChat(PatientCaregiverLink link) {
    final linkId = link.linkId;
    final medicationContexts = linkId == null
        ? const <ChatMedicationContext>[]
        : _medicationContextsByLink[linkId] ?? const [];
    if (_isLoading ||
        !widget.chatLabEnabled ||
        linkId == null ||
        !link.linkStatus) {
      return;
    }
    if (medicationContexts.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_text.chatUnavailable),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    final isCaregiver = link.caregiverHash == _committedUserHash;
    final peerName = isCaregiver
        ? (_patientLabels[link.patientHash] ?? _text.patientPeer)
        : _text.caregiverPeer;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LinkedChatUI(
          linkId: linkId,
          currentUserHash: _committedUserHash,
          patientHash: link.patientHash,
          peerName: peerName,
          initialMedicationContexts: medicationContexts,
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  Future<void> _showPatientCodeDialog(PatientLinkCode patientCode) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) =>
          _PatientCodeDialog(patientCode: patientCode, text: _text),
    );
  }

  Future<void> _showRegisterPatientDialog() {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => _RegisterPatientDialog(
        patientCodeController: _patientCodeController,
        onRegisterRequested: _requestPatientCaregiverLink,
        statusMessageProvider: () => _statusMessage,
        text: _text,
      ),
    );
  }
}

class _LinkRequest {
  final int generation;
  final String userHash;
  final LinkPatientCaregiver control;

  const _LinkRequest({
    required this.generation,
    required this.userHash,
    required this.control,
  });
}

class _LinkActionFooter extends StatelessWidget {
  final VoidCallback? onGeneratePatientCodeRequested;
  final VoidCallback? onRegisterPatientRequested;
  final _LinkPatientCaregiverText text;

  const _LinkActionFooter({
    required this.onGeneratePatientCodeRequested,
    required this.onRegisterPatientRequested,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LinkActionButton(
            icon: Icons.person_outline_rounded,
            title: text.generatePatientCode,
            subtitle: text.patientRole,
            semanticLabel: text.generatePatientCodeSemantic,
            onPressed: onGeneratePatientCodeRequested,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LinkActionButton(
            icon: Icons.health_and_safety_outlined,
            title: text.registerPatient,
            subtitle: text.caregiverRole,
            semanticLabel: text.registerPatientSemantic,
            onPressed: onRegisterPatientRequested,
          ),
        ),
      ],
    );
  }
}

class _LinkActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback? onPressed;

  const _LinkActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(92),
          foregroundColor: const Color(0xFF0A0A0A),
          backgroundColor: Colors.white,
          side: const BorderSide(color: MedBuddyColors.outline, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MedBuddyColors.primaryDark, size: 24),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String statusMessage;
  final bool isLoading;

  const _StatusCard({required this.statusMessage, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: MedBuddyColors.primary,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterPatientDialog extends StatefulWidget {
  final TextEditingController patientCodeController;
  final Future<bool> Function() onRegisterRequested;
  final String Function() statusMessageProvider;
  final _LinkPatientCaregiverText text;

  const _RegisterPatientDialog({
    required this.patientCodeController,
    required this.onRegisterRequested,
    required this.statusMessageProvider,
    required this.text,
  });

  @override
  State<_RegisterPatientDialog> createState() => _RegisterPatientDialogState();
}

class _RegisterPatientDialogState extends State<_RegisterPatientDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isRegistering = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: MedBuddyRadii.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 328),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: widget.text.close,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      onPressed: _isRegistering
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: MedBuddyColors.textMuted,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.text.registerPatient,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('patient-link-code'),
                  controller: widget.patientCodeController,
                  enabled: !_isRegistering,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(
                      PatientHash.patientLinkCodeLength,
                    ),
                    const _UpperCaseTextFormatter(),
                  ],
                  decoration: _inputDecoration(
                    widget.text.patientCodeLabel,
                    'ABCD1234',
                  ),
                  textInputAction: TextInputAction.done,
                  validator: _validatePatientCode,
                  onFieldSubmitted: (_) => _handleRegisterRequested(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _isRegistering ? null : _handleRegisterRequested,
                    style: FilledButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    child: _isRegistering
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(widget.text.register),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _validatePatientCode
  // 함수역할:
  // - 환자 연동 코드가 서버 규칙과 동일한 8자리 영문·숫자인지 검증한다.
  // 매개변수:
  // - value: 사용자가 입력한 환자 연동 코드
  // 반환값:
  // - 유효하면 null, 유효하지 않으면 화면에 표시할 오류 문구
  String? _validatePatientCode(String? value) {
    final patientCode = (value ?? '').trim();
    if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(patientCode)) {
      return widget.text.invalidPatientCode;
    }
    return null;
  }

  // 함수이름: _handleRegisterRequested
  // 함수역할:
  // - 입력값을 검증하고 같은 연동 요청이 연속으로 전송되지 않게 보호한다.
  // 반환값:
  // - 없음
  Future<void> _handleRegisterRequested() async {
    if (_isRegistering || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isRegistering = true);
    var success = false;
    try {
      success = await widget.onRegisterRequested();
    } catch (_) {
      success = false;
    }
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isRegistering = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.statusMessageProvider())));
  }
}

// 클래스명: _UpperCaseTextFormatter
// 역할: 환자 연동 코드 입력을 커서 위치를 유지한 채 대문자로 정규화한다.
class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _PatientCodeDialog extends StatefulWidget {
  final PatientLinkCode patientCode;
  final _LinkPatientCaregiverText text;

  const _PatientCodeDialog({required this.patientCode, required this.text});

  @override
  State<_PatientCodeDialog> createState() => _PatientCodeDialogState();
}

class _PatientCodeDialogState extends State<_PatientCodeDialog> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (widget.patientCode.isExpired()) {
        _countdownTimer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 328,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: MedBuddyRadii.card,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 19),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: widget.text.close,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF344054),
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.text.patientCodeDialogTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
                const SizedBox(height: 20),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.patientCode.code),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(widget.text.codeCopied)),
                      );
                    },
                    child: Container(
                      height: 57,
                      padding: const EdgeInsets.fromLTRB(18, 0, 14, 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: MedBuddyColors.outline,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.patientCode.code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1E2939),
                                fontSize: 16,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.copy_outlined,
                            color: Color(0xFF99A1AF),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.text.copyHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textSubtle,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 28),
                _PatientCodeNotice(
                  backgroundColor: MedBuddyColors.successSurface,
                  foregroundColor: MedBuddyColors.textBody,
                  text: widget.text.codeInstruction,
                ),
                const SizedBox(height: 15),
                _PatientCodeNotice(
                  backgroundColor: Color(0xFFFEF2F2),
                  foregroundColor: Color(0xFFE7000B),
                  fontWeight: FontWeight.w700,
                  text: widget.text.codeWarning,
                ),
                const SizedBox(height: 24),
                Text.rich(
                  TextSpan(
                    text: widget.text.remainingTime,
                    children: [
                      TextSpan(
                        text: _remainingTimeText,
                        style: const TextStyle(
                          color: MedBuddyColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textSubtle,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _remainingTimeText {
    final remaining = widget.patientCode.remaining();
    final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _PatientCodeNotice extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final FontWeight fontWeight;
  final String text;

  const _PatientCodeNotice({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.text,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 78,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: MedBuddyRadii.card,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: fontWeight,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LinkListCard extends StatelessWidget {
  final List<PatientCaregiverLink> links;
  final String currentUserHash;
  final bool isEnabled;
  final bool shrinkWrap;
  final Map<String, String> patientLabels;
  final bool showChatAction;
  final Map<int, List<ChatMedicationContext>> medicationContextsByLink;
  final void Function(PatientCaregiverLink link) onChatRequested;
  final void Function(PatientCaregiverLink link) onPatientMedicationRequested;
  final Future<void> Function(PatientCaregiverLink link)
  onPatientLabelRequested;
  final Future<void> Function(PatientCaregiverLink link) onUnlinkRequested;
  final _LinkPatientCaregiverText text;

  const _LinkListCard({
    required this.links,
    required this.currentUserHash,
    required this.isEnabled,
    this.shrinkWrap = false,
    required this.patientLabels,
    required this.showChatAction,
    required this.medicationContextsByLink,
    required this.onChatRequested,
    required this.onPatientMedicationRequested,
    required this.onPatientLabelRequested,
    required this.onUnlinkRequested,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: shrinkWrap,
      primary: shrinkWrap ? false : null,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: links.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final link = links[index];
        final linkId = link.linkId;
        final medicationContexts = linkId == null
            ? const <ChatMedicationContext>[]
            : medicationContextsByLink[linkId] ?? const [];
        return _LinkedUserTile(
          link: link,
          currentUserHash: currentUserHash,
          patientLabel: patientLabels[link.patientHash],
          showChatAction: showChatAction,
          isChatAvailable: medicationContexts.isNotEmpty,
          onChatRequested: isEnabled ? () => onChatRequested(link) : null,
          onPatientMedicationRequested: isEnabled
              ? () => onPatientMedicationRequested(link)
              : null,
          onPatientLabelRequested:
              isEnabled && link.caregiverHash == currentUserHash
              ? () => onPatientLabelRequested(link)
              : null,
          onUnlinkRequested: isEnabled ? () => onUnlinkRequested(link) : null,
          text: text,
        );
      },
    );
  }
}

class _LinkedUserTile extends StatelessWidget {
  final PatientCaregiverLink link;
  final String currentUserHash;
  final String? patientLabel;
  final bool showChatAction;
  final bool isChatAvailable;
  final VoidCallback? onChatRequested;
  final VoidCallback? onPatientMedicationRequested;
  final VoidCallback? onPatientLabelRequested;
  final VoidCallback? onUnlinkRequested;
  final _LinkPatientCaregiverText text;

  const _LinkedUserTile({
    required this.link,
    required this.currentUserHash,
    required this.patientLabel,
    required this.showChatAction,
    required this.isChatAvailable,
    required this.onChatRequested,
    required this.onPatientMedicationRequested,
    required this.onPatientLabelRequested,
    required this.onUnlinkRequested,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  patientLabel ?? text.linkInformation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0A0A0A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (showChatAction)
                IconButton(
                  tooltip: !isChatAvailable
                      ? text.chatUnavailable
                      : text.medicationChat,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  onPressed: onChatRequested,
                  icon: Icon(
                    Icons.chat_bubble_outline,
                    color: !isChatAvailable || onChatRequested == null
                        ? MedBuddyColors.textMuted
                        : MedBuddyColors.primary,
                  ),
                ),
              if (onPatientLabelRequested != null)
                IconButton(
                  tooltip: text.editPatientLabel,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  onPressed: onPatientLabelRequested,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: MedBuddyColors.primary,
                  ),
                ),
              if (_canOpenPatientMedication)
                IconButton(
                  tooltip: text.openPatientMedication,
                  onPressed: onPatientMedicationRequested,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.medication_outlined,
                    color: MedBuddyColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _LinkedIdentityField(
            label: text.patientHash,
            value: _displayHash(link.patientHash, text.noInformation),
          ),
          const SizedBox(height: 10),
          _LinkedIdentityField(
            label: text.caregiverHash,
            value: _displayHash(link.caregiverHash, text.noInformation),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onUnlinkRequested,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFB2C36),
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: Text(text.delete),
          ),
        ],
      ),
    );
  }

  bool get _canOpenPatientMedication {
    return link.linkStatus &&
        link.caregiverHash == currentUserHash &&
        link.patientHash.trim().isNotEmpty;
  }
}

class _LinkedIdentityField extends StatelessWidget {
  final String label;
  final String value;

  const _LinkedIdentityField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MedBuddyColors.outline, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label :',
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFF0A0A0A),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String labelText, String hintText) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: MedBuddyColors.surfaceSubtle,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MedBuddyColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MedBuddyColors.primary, width: 2),
    ),
  );
}

String _displayHash(String value, String fallback) {
  final displayValue = value.trim();
  if (displayValue.isEmpty) {
    return fallback;
  }
  return displayValue;
}

// 클래스명: _LinkPatientCaregiverText
// 역할: 환자·보호자 연동 화면에서 사용하는 문구를 언어별로 한곳에서 제공한다.
class _LinkPatientCaregiverText {
  final bool isEnglish;

  const _LinkPatientCaregiverText(String language)
    : isEnglish = language == 'en';

  String get close => isEnglish ? 'Close' : '닫기';
  String get screenTitle =>
      isEnglish ? 'Link Patient/Caregiver' : '환자/보호자 연동하기';
  String get loadingLinks =>
      isEnglish ? 'Loading linked accounts.' : '연동 정보를 불러오는 중입니다.';
  String get noSavedLinks =>
      isEnglish ? 'No linked accounts yet.' : '저장된 연동정보가 없습니다.';
  String linkCount(int count) => isEnglish
      ? '$count linked account${count == 1 ? '' : 's'}.'
      : '총 $count개의 연동이 있습니다.';
  String get codeGenerated => isEnglish
      ? 'Created a link code to share with a caregiver.'
      : '보호자에게 공유할 연동 코드를 생성했습니다.';
  String get enterPatientCode =>
      isEnglish ? 'Enter the patient link code.' : '등록할 환자 연동 코드를 입력해 주세요.';
  String get linkRegistered => isEnglish
      ? 'Patient and caregiver are now linked.'
      : '환자-보호자 연동을 등록했습니다.';
  String get missingLinkId => isEnglish
      ? 'This link cannot be removed because its identifier is missing.'
      : '연동 식별자가 없어 해제할 수 없습니다.';
  String get linkRemoved =>
      isEnglish ? 'Patient and caregiver link removed.' : '환자-보호자 연동을 해제했습니다.';
  String get linkedPatientOnly => isEnglish
      ? 'You can only view medication information for a linked patient.'
      : '연동된 환자의 복약 정보만 확인할 수 있습니다.';
  String get patientLabelTitle =>
      isEnglish ? 'Patient display name' : '환자 표시 이름';
  String get patientLabelHint =>
      isEnglish ? 'Example: Mom, Dad' : '예: 어머니, 아버지';
  String get patientLabelHelper => isEnglish
      ? 'This name is synced to your caregiver account.'
      : '이 이름은 보호자 계정에 동기화됩니다.';
  String get missingAliasLinkId => isEnglish
      ? 'This patient name cannot be saved because the link identifier is missing.'
      : '연동 식별자가 없어 환자 표시 이름을 저장할 수 없습니다.';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get save => isEnglish ? 'Save' : '저장';
  String patientLabelSaved(String label) =>
      isEnglish ? 'Saved the display name $label.' : '$label 표시 이름을 저장했습니다.';
  String get patientPeer => isEnglish ? 'Patient' : '환자';
  String get caregiverPeer => isEnglish ? 'Caregiver' : '보호자';
  String get generatePatientCode =>
      isEnglish ? 'Create patient code' : '환자 코드 생성';
  String get patientRole =>
      isEnglish ? 'Patient taking medication' : '약을 복용하는 환자';
  String get generatePatientCodeSemantic => isEnglish
      ? 'Create a patient link code to share with a caregiver.'
      : '약을 복용하는 환자입니다. 보호자에게 전달할 연동 코드를 만듭니다.';
  String get registerPatient => isEnglish ? 'Register patient' : '환자 관리 등록';
  String get caregiverRole =>
      isEnglish ? 'Caregiver checking medication' : '복약을 확인하는 보호자';
  String get registerPatientSemantic => isEnglish
      ? 'Register the link code received from a patient.'
      : '복약을 확인하는 보호자입니다. 환자에게 받은 연동 코드를 등록합니다.';
  String get patientCodeLabel => isEnglish ? 'Patient code' : '환자 코드';
  String get register => isEnglish ? 'Register' : '등록하기';
  String get invalidPatientCode => isEnglish
      ? 'Enter an 8-character code using letters and numbers.'
      : '환자 코드는 영문과 숫자 8자리로 입력해 주세요.';
  String get patientCodeDialogTitle => isEnglish ? 'Patient code' : '환자 코드 생성';
  String get codeCopied => isEnglish ? 'Code copied.' : '코드를 복사했습니다.';
  String get copyHint =>
      isEnglish ? '(Tap the code to copy)' : '(코드를 클릭하면 복사됩니다)';
  String get codeInstruction => isEnglish
      ? 'Register this code on the caregiver phone.'
      : '해당 코드를 보호자 휴대폰에\n등록해주세요';
  String get codeWarning => isEnglish
      ? 'Share this code only with your caregiver.'
      : '해당 코드를 보호자 외\n다른 사람과 공유하지 마세요!';
  String get remainingTime => isEnglish ? 'Time left: ' : '남은 시간: ';
  String get linkInformation => isEnglish ? 'Linked account' : '연동 정보';
  String get chatUnavailable => isEnglish
      ? 'Chat is unavailable because the patient has no active medication.'
      : '현재 복용 중인 약이 없어 채팅을 시작할 수 없습니다.';
  String get medicationChat => isEnglish ? 'Medication chat' : '복약 대화';
  String get editPatientLabel =>
      isEnglish ? 'Edit patient display name' : '환자 표시 이름 수정';
  String get openPatientMedication =>
      isEnglish ? 'View patient medication' : '환자 복약 정보 확인';
  String get patientHash => isEnglish ? 'Patient ID' : '환자 해시';
  String get caregiverHash => isEnglish ? 'Caregiver ID' : '보호자 해시';
  String get delete => isEnglish ? 'Remove link' : '삭제하기';
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
}
