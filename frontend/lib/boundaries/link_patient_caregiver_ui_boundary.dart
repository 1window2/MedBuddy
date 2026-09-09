// File Name: link_patient_caregiver_ui_boundary.dart
// Role: UI boundaries and helpers for patient-code generation, registration, and patient-caregiver link management.

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

// 함수이름: LinkPatientCaregiverFactory
// 함수역할: 사용자 해시 범위에 맞춘 연동 컨트롤러를 생성하는 콜백 계약이다.
// 매개변수:
// - userHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// 반환값: LinkPatientCaregiver: 지정 사용자 범위의 환자·보호자 연동 컨트롤러.
typedef LinkPatientCaregiverFactory =
    LinkPatientCaregiver Function(String userHash);
// 함수이름: LinkedChatControlFactory
// 함수역할: 사용자 해시 범위에 맞춘 채팅 컨트롤러를 생성하는 콜백 계약이다.
// 매개변수:
// - userHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// 반환값: ManageLinkedChat: 지정 사용자 범위의 연동 채팅 컨트롤러.
typedef LinkedChatControlFactory = ManageLinkedChat Function(String userHash);

// 파일명: link_patient_caregiver_ui_boundary.dart
// 역할: 환자와 보호자 연동을 관리하는 화면을 구성한다.

// 클래스명: LinkPatientCaregiverUI
// 역할: 환자 코드 발급·등록과 연동 목록을 담당한다.
// 주요 책임:
// - 현재 사용자 해시 기준 연동 목록을 조회한다.
// - 환자용 임시 코드를 생성해 보호자에게 전달할 수 있게 한다.
// - 보호자가 환자 코드를 입력해 연동을 등록할 수 있게 한다.
// 속성:
// - initialUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// - chatLabEnabled (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - controlFactory (LinkPatientCaregiverFactory?): 사용자 해시별 연동 컨트롤러 생성 함수.
class LinkPatientCaregiverUI extends StatefulWidget {
  final String initialUserHash;
  final bool chatLabEnabled;
  final UserSetting userSetting;
  final LinkPatientCaregiverFactory? controlFactory;
  final LinkedChatControlFactory? chatControlFactory;

  // 함수이름: LinkPatientCaregiverUI
  // 함수역할: 환자 코드 발급·등록과 연동 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - initialUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // - chatLabEnabled (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - controlFactory (LinkPatientCaregiverFactory?): 사용자 해시별 연동 컨트롤러 생성 함수.
  // - chatControlFactory (LinkedChatControlFactory?): 사용자 해시별 채팅 컨트롤러 생성 함수.
  // 반환값: 입력 설정이 반영된 LinkPatientCaregiverUI 인스턴스.
  const LinkPatientCaregiverUI({
    super.key,
    this.initialUserHash = PatientHash.defaultPatientHash,
    this.chatLabEnabled = false,
    this.userSetting = const UserSetting(),
    this.controlFactory,
    this.chatControlFactory,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates patient-code generation, registration, and linked-user lists.
  // Parameters:
  // - None.
  // Returns: A new _LinkPatientCaregiverUIState instance.
  @override
  State<LinkPatientCaregiverUI> createState() => _LinkPatientCaregiverUIState();
}

// 클래스명: _LinkPatientCaregiverUIState
// 역할: 환자 코드 발급·등록과 연동 목록의 화면 상태를 관리한다.
// 주요 책임:
// - 연동 목록·환자 별칭·채팅 약품을 조회하고 여전히 유효한 요청의 결과만 반영한다.
// - 임시 환자 코드를 발급해 대화상자로 보여주고 닫힌 뒤 연동 목록을 갱신한다.
// - 빈 코드를 거절하고 연동 등록 후 목록·별칭·채팅 맥락을 갱신한다.
// 속성:
// - _patientCodeController (TextEditingController): 환자 연결 코드를 입력·검증할 텍스트 컨트롤러.
// - _control (LinkPatientCaregiver): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - _links (List<PatientCaregiverLink>): 표시하거나 관련 정보를 조회할 연동 목록.
// - _patientLabels (Map<String, String>): 환자 해시별 저장된 표시 별칭.
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

  // 함수이름: initState
  // 함수역할: 사용자 해시를 정규화하고 연동·채팅 컨트롤러와 코드 입력을 준비해 초기 조회를 예약한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // 함수이름: didUpdateWidget
  // 함수역할: 사용자·언어·채팅 설정 변경을 감지해 필요한 컨트롤러를 교체하고 연동 표시를 다시 조회한다.
  // 매개변수:
  // - oldWidget (LinkPatientCaregiverUI): 변경 전 입력값과 비교할 이전 위젯.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // 함수이름: dispose
  // 함수역할: _control, _chatControl, _patientCodeController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _requestGeneration += 1;
    _control.dispose();
    _chatControl.dispose();
    _patientCodeController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 코드 발급·등록과 연동 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 코드 발급·등록과 연동 목록에 쓰는 위젯 트리.
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
  // 함수역할: 일반 화면에서는 연동 목록이 남은 공간을 채우게 배치한다. 작은 화면이나 큰 글씨에서는 전체 내용을 한 번에 스크롤할 수 있게 배치한다.
  // 매개변수:
  // - usesScrollableList (bool): 상위 스크롤 레이아웃에 맞춰 콘텐츠 크기를 제한할지 여부.
  // 반환값: 환자 코드 발급·등록과 연동 목록에 쓰는 위젯 트리.
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
          // Function Name: _buildLinkContent.onPressed callback
          // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
          // Parameters:
          // - None.
          // Returns: No callback payload; any selection is delivered through the route result.
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

  // 함수이름: _text
  // 함수역할: 현재 언어에 맞는 환자 코드 발급·등록과 환자·보호자 연결 관리 문구 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: _LinkPatientCaregiverText: 현재 화면 언어의 문구 제공 객체.
  _LinkPatientCaregiverText get _text =>
      _LinkPatientCaregiverText(widget.userSetting.language);

  // 함수이름: _refreshLinks
  // 함수역할: 연동 목록·환자 별칭·채팅 약품을 조회하고 여전히 유효한 요청의 결과만 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _refreshLinks() async {
    // 함수이름: _refreshLinks._runLinkAction callback
    // 함수역할: 화면 유지·요청 세대·사용자 해시·컨트롤러 동일성을 함께 확인한다.
    // 매개변수:
    // - request (콜백 계약에서 추론): 작업 세대·사용자·컨트롤러를 묶은 요청 맥락.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
      // 함수이름: _refreshLinks.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_links = links; _patientLabels = labels; _medicationContextsByLink = medicationContexts`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _generatePatientHash
  // 함수역할: 임시 환자 코드를 발급해 대화상자로 보여주고 닫힌 뒤 연동 목록을 갱신한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _generatePatientHash() async {
    PatientLinkCode? patientCode;
    // 함수이름: _generatePatientHash._runLinkAction callback
    // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `patientCode = generatedCode`로 갱신한다.
    // 매개변수:
    // - request (콜백 계약에서 추론): 작업 세대·사용자·컨트롤러를 묶은 요청 맥락.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    final request = await _runLinkAction((request) async {
      final generatedCode = await request.control.generatePatientHash();
      if (!_isCurrentRequest(request)) {
        return;
      }
      patientCode = generatedCode;
      // 함수이름: _generatePatientHash.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = _text.codeGenerated`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _requestPatientCaregiverLink
  // 함수역할: 빈 코드를 거절하고 연동 등록 후 목록·별칭·채팅 맥락을 갱신한다.
  // 매개변수:
  // - 없음.
  // 반환값: 성공하면 true, 실패하거나 요청을 수행하지 못하면 false로 완료되는 Future.
  Future<bool> _requestPatientCaregiverLink() async {
    if (_isLoading || !mounted) {
      return false;
    }

    final patientCode = _patientCodeController.text.trim();
    if (patientCode.isEmpty) {
      // 함수이름: _requestPatientCaregiverLink.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = _text.enterPatientCode`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _statusMessage = _text.enterPatientCode;
      });
      return false;
    }

    var registered = false;
    // 함수이름: _requestPatientCaregiverLink._runLinkAction callback
    // 함수역할: 화면 유지·요청 세대·사용자 해시·컨트롤러 동일성을 함께 확인한다.
    // 매개변수:
    // - request (콜백 계약에서 추론): 작업 세대·사용자·컨트롤러를 묶은 요청 맥락.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
      // 함수이름: _requestPatientCaregiverLink.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_links = links; _patientLabels = labels; _medicationContextsByLink = medicationContexts`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _removePatientCaregiverLink
  // 함수역할: 연결 ID를 확인해 연동을 해제하고 로컬 환자 상태를 정리한 뒤 목록을 갱신한다.
  // 매개변수:
  // - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _removePatientCaregiverLink(PatientCaregiverLink link) async {
    if (_isLoading || !mounted) {
      return;
    }

    final linkId = link.linkId;
    if (linkId == null) {
      // 함수이름: _removePatientCaregiverLink.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = _text.missingLinkId`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _statusMessage = _text.missingLinkId;
      });
      return;
    }

    // 함수이름: _removePatientCaregiverLink._runLinkAction callback
    // 함수역할: 화면 유지·요청 세대·사용자 해시·컨트롤러 동일성을 함께 확인한다.
    // 매개변수:
    // - request (콜백 계약에서 추론): 작업 세대·사용자·컨트롤러를 묶은 요청 맥락.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
      // 함수이름: _removePatientCaregiverLink.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_links = links; _patientLabels = labels; _medicationContextsByLink = medicationContexts`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _links = links;
        _patientLabels = labels;
        _medicationContextsByLink = medicationContexts;
        _statusMessage = _text.linkRemoved;
      });
    });
  }

  // 함수이름: _loadPatientLabels
  // 함수역할: 현재 보호자가 연결한 환자별 표시 이름을 로컬 저장소에서 읽는다.
  // 매개변수:
  // - links (List<PatientCaregiverLink>): 표시하거나 관련 정보를 조회할 연동 목록.
  // 반환값: Future<Map<String, String>>: 환자 해시별 표시 별칭.
  Future<Map<String, String>> _loadPatientLabels(
    List<PatientCaregiverLink> links,
  ) async {
    return _localStateControl.loadLabels(
      caregiverHash: _committedUserHash,
      links: links,
    );
  }

  // 함수이름: _loadChatMedicationContexts
  // 함수역할: 실험 기능이 켜졌을 때 각 연동 환자의 활성 복약 목록을 병렬로 불러온다. 한 연동의 조회 실패가 다른 환자의 연동 목록까지 막지 않게 빈 목록으로 격리한다.
  // 매개변수:
  // - links (List<PatientCaregiverLink>): 표시하거나 관련 정보를 조회할 연동 목록.
  // 반환값: Future<Map<int, List<ChatMedicationContext>>>: 유효 연동별 약품 맥락; 조회 실패 항목은 빈 목록.
  Future<Map<int, List<ChatMedicationContext>>> _loadChatMedicationContexts(
    List<PatientCaregiverLink> links,
  ) async {
    if (!widget.chatLabEnabled) {
      return const {};
    }
    final entries = await Future.wait(
      // 함수이름: _loadChatMedicationContexts.map callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 변환값을 `null; MapEntry(linkId, medications); MapEntry<int, List<ChatMedicationContext>>(linkId, const [])` 규칙으로 계산한다.
      // 매개변수:
      // - link (콜백 계약에서 추론): 환자·보호자 연결과 권한 상태.
      // 반환값: 컬렉션 연산에 전달할 변환값.
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

  // 함수이름: _runLinkAction
  // 함수역할: 중복 실행을 막고 사용자·세대가 유지된 요청에만 로딩·오류 결과를 반영한다.
  // 매개변수:
  // - action (Future<void> Function(_LinkRequest request)): 현재 요청 맥락에서 수행할 비동기 연동 작업.
  // 반환값: Future<_LinkRequest?>: 아직 유효한 완료 요청 맥락; 실패·생략·무효화되면 null.
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
    // Function Name: _runLinkAction.setState callback
    // Description: Updates the local input or request state for patient-code generation, registration, and linked-user lists: `_isLoading = true`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _isLoading = true;
    });

    try {
      await action(request);
      return _isCurrentRequest(request) ? request : null;
    } catch (error) {
      if (_isCurrentRequest(request)) {
        // 함수이름: _runLinkAction.setState callback
        // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = UserFacingErrorMessage.resolve(error, isEnglish: _text.isEnglish)`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
        // Function Name: _runLinkAction.setState callback
        // Description: Updates the local input or request state for patient-code generation, registration, and linked-user lists: `_isLoading = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Function Name: _scheduleRefresh
  // Description: Refreshes links after the frame only if the request generation is still current.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  void _scheduleRefresh() {
    final generation = _requestGeneration;
    // Function Name: _scheduleRefresh.addPostFrameCallback callback
    // Description: Loads links, patient aliases, and chat medications, applying only results belonging to the current request.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      _refreshLinks();
    });
  }

  // 함수이름: _replaceControl
  // 함수역할: 사용자가 바뀌면 이전 요청을 무효화하고 연동·채팅 컨트롤러를 새 계정으로 교체한다.
  // 매개변수:
  // - userHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // Function Name: _createControl
  // Description: Creates a patient-caregiver link controller from the injected factory or default implementation for the user hash.
  // Parameters:
  // - userHash (String): User hash defining the account scope of the operation.
  // Returns: LinkPatientCaregiver: Patient-caregiver link controller scoped to the given user.
  LinkPatientCaregiver _createControl(String userHash) {
    return widget.controlFactory?.call(userHash) ??
        LinkPatientCaregiver(userHash: userHash);
  }

  // 함수이름: _createChatControl
  // 함수역할: 사용자 해시로 주입된 팩토리 또는 기본 연동 채팅 컨트롤러를 만든다.
  // 매개변수:
  // - userHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // 반환값: ManageLinkedChat: 지정 사용자 범위의 연동 채팅 컨트롤러.
  ManageLinkedChat _createChatControl(String userHash) {
    return widget.chatControlFactory?.call(userHash) ??
        ManageLinkedChat(userHash: userHash);
  }

  // Function Name: _isCurrentRequest
  // Description: Checks mounted state, request generation, user hash, and controller identity together.
  // Parameters:
  // - request (_LinkRequest): Request context containing generation, user, and controller.
  // Returns: True when the documented condition holds; false otherwise.
  bool _isCurrentRequest(_LinkRequest request) {
    return mounted &&
        request.generation == _requestGeneration &&
        request.userHash == _committedUserHash &&
        identical(request.control, _control);
  }

  // 함수이름: _showPatientLabelDialog
  // 함수역할: 보호자가 여러 환자를 쉽게 구분하도록 환자별 표시 이름을 입력받아 저장한다.
  // 매개변수:
  // - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showPatientLabelDialog(PatientCaregiverLink link) async {
    if (link.caregiverHash != _committedUserHash || !mounted) {
      return;
    }
    var draftLabel =
        _patientLabels[link.patientHash] ??
        _localStateControl.fallbackLabel(link.patientHash);
    final submittedLabel = await showDialog<String>(
      context: context,
      // 함수이름: _showPatientLabelDialog.builder callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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
            // 함수이름: _showPatientLabelDialog.onChanged callback
            // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `draftLabel = value`로 갱신한다.
            // 매개변수:
            // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
            onChanged: (value) => draftLabel = value,
            // 함수이름: _showPatientLabelDialog.onFieldSubmitted callback
            // 함수역할: `Navigator.pop(dialogContext, value)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              // 함수이름: _showPatientLabelDialog.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_text.cancel),
            ),
            FilledButton(
              // 함수이름: _showPatientLabelDialog.onPressed callback
              // 함수역할: `Navigator.pop(dialogContext, draftLabel)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
              // 매개변수:
              // - 없음.
              // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
      // 함수이름: _showPatientLabelDialog.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = _text.missingAliasLinkId`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _statusMessage = _text.missingAliasLinkId;
      });
      return;
    }
    String? savedLabel;
    // 함수이름: _showPatientLabelDialog._runLinkAction callback
    // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `savedLabel = await _localStateControl.saveLabel(caregiverHash: link.caregiverHash, patientHash: l...`로 갱신한다.
    // 매개변수:
    // - request (콜백 계약에서 추론): 작업 세대·사용자·컨트롤러를 묶은 요청 맥락.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
      // 함수이름: _showPatientLabelDialog.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_links = _links.map((currentLink) => currentLink.linkId == linkId ? updatedLink : currentLink).to...; _patientLabels = {..._patientLabels, link.patientHash : savedLabel!}`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _links = _links
            .map(
              // 함수이름: _showPatientLabelDialog.map callback
              // 함수역할: 환자 코드 발급·등록과 연동 목록의 변환값을 `currentLink.linkId == linkId ? updatedLink : currentLink` 규칙으로 계산한다.
              // 매개변수:
              // - currentLink (콜백 계약에서 추론): 별칭 갱신 대상 ID와 비교할 기존 연결.
              // 반환값: 컬렉션 연산에 전달할 변환값.
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

  // 함수이름: _openPatientMedicationInfo
  // 함수역할: 현재 사용자의 유효한 보호자 연결일 때 환자 별칭과 설정을 전달해 오늘 복약 화면을 연다.
  // 매개변수:
  // - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _openPatientMedicationInfo(PatientCaregiverLink link) {
    if (_isLoading) {
      return;
    }

    final caregiverHash = _committedUserHash;
    if (!link.linkStatus ||
        link.caregiverHash != caregiverHash ||
        link.patientHash.trim().isEmpty) {
      // 함수이름: _openPatientMedicationInfo.setState callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록의 입력·요청 상태를 `_statusMessage = _text.linkedPatientOnly`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _statusMessage = _text.linkedPatientOnly;
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 함수이름: _openPatientMedicationInfo.builder callback
        // 함수역할: 환자 코드 발급·등록과 연동 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (context) => CheckCaregiverMedicationUI(
          caregiverHash: caregiverHash,
          patientHash: link.patientHash,
          patientLabel: _patientLabels[link.patientHash],
          userSetting: widget.userSetting,
        ),
      ),
    );
  }

  // 함수이름: _openLinkedChat
  // 함수역할: 현재 사용자가 참여한 연동의 실시간 가족 채팅 화면을 연다.
  // 매개변수:
  // - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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
        // 함수이름: _openLinkedChat.builder callback
        // 함수역할: 환자 코드 발급·등록과 연동 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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

  // 함수이름: _showPatientCodeDialog
  // 함수역할: 발급된 환자 코드와 만료 안내 대화상자를 연다.
  // 매개변수:
  // - patientCode (PatientLinkCode): 발급된 임시 연결 코드와 만료 정보.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showPatientCodeDialog(PatientLinkCode patientCode) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      // 함수이름: _showPatientCodeDialog.builder callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) =>
          _PatientCodeDialog(patientCode: patientCode, text: _text),
    );
  }

  // 함수이름: _showRegisterPatientDialog
  // 함수역할: 공유 코드 입력·등록 요청·상태 문구를 연결한 환자 등록 창을 연다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showRegisterPatientDialog() {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      // 함수이름: _showRegisterPatientDialog.builder callback
      // 함수역할: 환자 코드 발급·등록과 연동 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) => _RegisterPatientDialog(
        patientCodeController: _patientCodeController,
        onRegisterRequested: _requestPatientCaregiverLink,
        // Function Name: _showRegisterPatientDialog.statusMessageProvider callback
        // Description: Supplies `_statusMessage` from the captured state of patient-code generation, registration, and linked-user lists.
        // Parameters:
        // - None.
        // Returns: The value of `_statusMessage`.
        statusMessageProvider: () => _statusMessage,
        text: _text,
      ),
    );
  }
}

// Class Name: _LinkRequest
// Role: Represents a link request's generation, user hash, and controller context.
// Responsibilities:
// - Groups the supplied field values for a link request's generation, user hash, and controller context in a single object.
// Attributes:
// - generation (int): Request generation used to reject stale asynchronous results.
// - userHash (String): User hash defining the account scope of the operation.
// - control (LinkPatientCaregiver): Controller handling this screen's queries and update requests.
class _LinkRequest {
  final int generation;
  final String userHash;
  final LinkPatientCaregiver control;

  // Function Name: _LinkRequest
  // Description: Combines the supplied values for a link request's generation, user hash, and controller context in a _LinkRequest instance.
  // Parameters:
  // - generation (int): Request generation used to reject stale asynchronous results.
  // - userHash (String): User hash defining the account scope of the operation.
  // - control (LinkPatientCaregiver): Controller handling this screen's queries and update requests.
  // Returns: Initialized _LinkRequest instance.
  const _LinkRequest({
    required this.generation,
    required this.userHash,
    required this.control,
  });
}

// 클래스명: _LinkActionFooter
// 역할: 환자 코드 생성과 보호자 등록 진입 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 환자 코드 생성과 보호자 등록 진입 명령 위젯을 구성한다.
// 속성:
// - onGeneratePatientCodeRequested (VoidCallback?): 환자용 임시 연결 코드를 발급할 콜백.
// - onRegisterPatientRequested (VoidCallback?): 입력한 환자 코드를 등록할 콜백.
class _LinkActionFooter extends StatelessWidget {
  final VoidCallback? onGeneratePatientCodeRequested;
  final VoidCallback? onRegisterPatientRequested;
  final _LinkPatientCaregiverText text;

  // 함수이름: _LinkActionFooter
  // 함수역할: 환자 코드 생성과 보호자 등록 진입 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - onGeneratePatientCodeRequested (VoidCallback?): 환자용 임시 연결 코드를 발급할 콜백.
  // - onRegisterPatientRequested (VoidCallback?): 입력한 환자 코드를 등록할 콜백.
  // - text (_LinkPatientCaregiverText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _LinkActionFooter 인스턴스.
  const _LinkActionFooter({
    required this.onGeneratePatientCodeRequested,
    required this.onRegisterPatientRequested,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 코드 생성과 보호자 등록 진입 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 코드 생성과 보호자 등록 진입 명령에 쓰는 위젯 트리.
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

// 클래스명: _LinkActionButton
// 역할: 환자 연동 작업의 아이콘·제목·실행 상태를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 환자 연동 작업의 아이콘·제목·실행 상태 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - subtitle (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - semanticLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
class _LinkActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback? onPressed;

  // 함수이름: _LinkActionButton
  // 함수역할: 환자 연동 작업의 아이콘·제목·실행 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - subtitle (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - semanticLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _LinkActionButton 인스턴스.
  const _LinkActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 연동 작업의 아이콘·제목·실행 상태 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 연동 작업의 아이콘·제목·실행 상태에 쓰는 위젯 트리.
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

// 클래스명: _StatusCard
// 역할: 환자·보호자 연결 작업 결과 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 환자·보호자 연결 작업 결과 안내 위젯을 구성한다.
// 속성:
// - statusMessage (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - isLoading (bool): 진행 중 표시를 보여줄지 여부.
class _StatusCard extends StatelessWidget {
  final String statusMessage;
  final bool isLoading;

  // 함수이름: _StatusCard
  // 함수역할: 환자·보호자 연결 작업 결과 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - statusMessage (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - isLoading (bool): 진행 중 표시를 보여줄지 여부.
  // 반환값: 입력 설정이 반영된 _StatusCard 인스턴스.
  const _StatusCard({required this.statusMessage, required this.isLoading});

  // Function Name: build
  // Description: Renders the result notice for patient-caregiver link operations from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the result notice for patient-caregiver link operations.
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

// 클래스명: _RegisterPatientDialog
// 역할: 환자 코드 입력과 연결 등록을 담당한다.
// 주요 책임:
// - 환자 코드 입력과 연결 등록의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - patientCodeController (TextEditingController): 환자 연결 코드를 입력·검증할 텍스트 컨트롤러.
// - onRegisterRequested (Future<bool> Function()): 입력한 환자 코드를 등록할 콜백.
// - statusMessageProvider (String Function()): 작업 후 최신 상태 안내를 읽는 함수.
class _RegisterPatientDialog extends StatefulWidget {
  final TextEditingController patientCodeController;
  final Future<bool> Function() onRegisterRequested;
  final String Function() statusMessageProvider;
  final _LinkPatientCaregiverText text;

  // 함수이름: _RegisterPatientDialog
  // 함수역할: 환자 코드 입력과 연결 등록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - patientCodeController (TextEditingController): 환자 연결 코드를 입력·검증할 텍스트 컨트롤러.
  // - onRegisterRequested (Future<bool> Function()): 입력한 환자 코드를 등록할 콜백.
  // - statusMessageProvider (String Function()): 작업 후 최신 상태 안내를 읽는 함수.
  // - text (_LinkPatientCaregiverText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _RegisterPatientDialog 인스턴스.
  const _RegisterPatientDialog({
    required this.patientCodeController,
    required this.onRegisterRequested,
    required this.statusMessageProvider,
    required this.text,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates patient-code entry and link registration.
  // Parameters:
  // - None.
  // Returns: A new _RegisterPatientDialogState instance.
  @override
  State<_RegisterPatientDialog> createState() => _RegisterPatientDialogState();
}

// 클래스명: _RegisterPatientDialogState
// 역할: 환자 코드 입력과 연결 등록의 화면 상태를 관리한다.
// 주요 책임:
// - 환자 코드 입력과 연결 등록에 필요한 상태 변경과 사용자 동작을 연결한다.
class _RegisterPatientDialogState extends State<_RegisterPatientDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isRegistering = false;

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 코드 입력과 연결 등록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 코드 입력과 연결 등록에 쓰는 위젯 트리.
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
                          // 함수이름: build.onPressed callback
                          // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
                  // 함수이름: build.onFieldSubmitted callback
                  // 함수역할: 환자 코드 입력과 연결 등록에서 캡처된 작업 `_handleRegisterRequested()`을 실행한다.
                  // 매개변수:
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
  // 함수역할: 환자 연동 코드가 서버 규칙과 동일한 8자리 영문·숫자인지 검증한다.
  // 매개변수:
  // - value (String?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? _validatePatientCode(String? value) {
    final patientCode = (value ?? '').trim();
    if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(patientCode)) {
      return widget.text.invalidPatientCode;
    }
    return null;
  }

  // 함수이름: _handleRegisterRequested
  // 함수역할: 입력값을 검증하고 같은 연동 요청이 연속으로 전송되지 않게 보호한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _handleRegisterRequested() async {
    if (_isRegistering || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    // Function Name: _handleRegisterRequested.setState callback
    // Description: Updates the local input or request state for patient-code entry and link registration: `_isRegistering = true`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
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
    // Function Name: _handleRegisterRequested.setState callback
    // Description: Updates the local input or request state for patient-code entry and link registration: `_isRegistering = false`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() => _isRegistering = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.statusMessageProvider())));
  }
}

// 클래스명: _UpperCaseTextFormatter
// 역할: 선택 영역을 유지하는 환자 코드 대문자 변환을 담당한다.
// 주요 책임:
// - 새 입력의 선택·조합 정보를 보존한 채 텍스트만 대문자로 바꾼다.
class _UpperCaseTextFormatter extends TextInputFormatter {
  // 함수이름: _UpperCaseTextFormatter
  // 함수역할: 선택 영역을 유지하는 환자 코드 대문자 변환 관련 값을 _UpperCaseTextFormatter 인스턴스에 담는다.
  // 매개변수:
  // - 없음.
  // 반환값: 입력 설정이 반영된 _UpperCaseTextFormatter 인스턴스.
  const _UpperCaseTextFormatter();

  // 함수이름: formatEditUpdate
  // 함수역할: 새 입력의 선택·조합 정보를 보존한 채 텍스트만 대문자로 바꾼다.
  // 매개변수:
  // - oldValue (TextEditingValue): 변경 이전 입력값과 선택 영역.
  // - newValue (TextEditingValue): 새로 입력된 텍스트와 선택 영역.
  // 반환값: TextEditingValue: 텍스트만 대문자로 바뀌고 선택·조합 영역은 유지된 입력값.
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

// 클래스명: _PatientCodeDialog
// 역할: 환자 코드와 만료 시간·재발급·복사 명령을 담당한다.
// 주요 책임:
// - 환자 코드와 만료 시간·재발급·복사 명령의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - patientCode (PatientLinkCode): 발급된 임시 연결 코드와 만료 정보.
class _PatientCodeDialog extends StatefulWidget {
  final PatientLinkCode patientCode;
  final _LinkPatientCaregiverText text;

  // 함수이름: _PatientCodeDialog
  // 함수역할: 환자 코드와 만료 시간·재발급·복사 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - patientCode (PatientLinkCode): 발급된 임시 연결 코드와 만료 정보.
  // - text (_LinkPatientCaregiverText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _PatientCodeDialog 인스턴스.
  const _PatientCodeDialog({required this.patientCode, required this.text});

  // Function Name: createState
  // Description: Creates the state object that coordinates a patient code, expiry time, regeneration, and copy actions.
  // Parameters:
  // - None.
  // Returns: A new _PatientCodeDialogState instance.
  @override
  State<_PatientCodeDialog> createState() => _PatientCodeDialogState();
}

// 클래스명: _PatientCodeDialogState
// 역할: 환자 코드와 만료 시간·재발급·복사 명령의 화면 상태를 관리한다.
// 주요 책임:
// - 환자 코드와 만료 시간·재발급·복사 명령에 필요한 상태 변경과 사용자 동작을 연결한다.
class _PatientCodeDialogState extends State<_PatientCodeDialog> {
  Timer? _countdownTimer;

  // Function Name: initState
  // Description: Refreshes the remaining validity each second and stops the timer when the code expires.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    // Function Name: initState.periodic callback
    // Description: Connects a patient code, expiry time, regeneration, and copy actions to the captured operation `widget.patientCode.isExpired(); _countdownTimer?.cancel()`.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (widget.patientCode.isExpired()) {
        _countdownTimer?.cancel();
      }
      // Function Name: initState.setState callback
      // Description: Intentionally leaves captured values unchanged; the caller controls rebuilding or disables this interaction.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      setState(() {});
    });
  }

  // Function Name: dispose
  // Description: Releases _countdownTimer and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 코드와 만료 시간·재발급·복사 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 코드와 만료 시간·재발급·복사 명령에 쓰는 위젯 트리.
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
                      // Function Name: build.onPressed callback
                      // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
                      // Parameters:
                      // - None.
                      // Returns: No callback payload; any selection is delivered through the route result.
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
                    // 함수이름: build.onTap callback
                    // 함수역할: 환자 코드와 만료 시간·재발급·복사 명령에서 캡처된 작업 `Clipboard.setData(ClipboardData(text: widget.patientCode.code)); ClipboardData(text: widget.patientCode.code)`을 실행한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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

  // Function Name: _remainingTimeText
  // Description: Rounds remaining code-validity milliseconds up to seconds and formats two-digit minutes:seconds.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get _remainingTimeText {
    final remaining = widget.patientCode.remaining();
    final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

// 클래스명: _PatientCodeNotice
// 역할: 환자 코드 전달 시 주의 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 환자 코드 전달 시 주의 안내 위젯을 구성한다.
// 속성:
// - backgroundColor (Color): 항목의 바탕 색상.
// - foregroundColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - fontWeight (FontWeight): 강조 정도를 지정할 글꼴 두께.
class _PatientCodeNotice extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final FontWeight fontWeight;
  final String text;

  // Function Name: _PatientCodeNotice
  // Description: Initializes the notice accompanying patient-code sharing with the supplied configuration.
  // Parameters:
  // - backgroundColor (Color): Background color for the item.
  // - foregroundColor (Color): Foreground or accent color applied to text, icons, or state guidance.
  // - text (String): Text content to display in this label or information row.
  // - fontWeight (FontWeight): Font weight defining emphasis.
  // Returns: Initialized _PatientCodeNotice instance.
  const _PatientCodeNotice({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.text,
    this.fontWeight = FontWeight.w500,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 환자 코드 전달 시 주의 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 환자 코드 전달 시 주의 안내에 쓰는 위젯 트리.
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

// 클래스명: _LinkListCard
// 역할: 연동된 환자 또는 보호자 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 연동된 환자 또는 보호자 목록 위젯을 구성한다.
// 속성:
// - links (List<PatientCaregiverLink>): 표시하거나 관련 정보를 조회할 연동 목록.
// - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
// - shrinkWrap (bool): 상위 스크롤 레이아웃에 맞춰 콘텐츠 크기를 제한할지 여부.
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

  // 함수이름: _LinkListCard
  // 함수역할: 연동된 환자 또는 보호자 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - links (List<PatientCaregiverLink>): 표시하거나 관련 정보를 조회할 연동 목록.
  // - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - shrinkWrap (bool): 상위 스크롤 레이아웃에 맞춰 콘텐츠 크기를 제한할지 여부.
  // - patientLabels (Map<String, String>): 환자 해시별 저장된 표시 별칭.
  // - showChatAction (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
  // - medicationContextsByLink (Map<int, List<ChatMedicationContext>>): 연동 ID별 채팅에 사용할 약품 맥락.
  // - onChatRequested (void Function(PatientCaregiverLink link)): 연동 사용자와의 복약 대화를 여는 콜백.
  // - onPatientMedicationRequested (void Function(PatientCaregiverLink link)): 연동 환자의 오늘 복약 상태를 여는 콜백.
  // - onPatientLabelRequested (Future<void> Function(PatientCaregiverLink link)): 연동 환자의 표시 별칭을 수정할 콜백.
  // - onUnlinkRequested (Future<void> Function(PatientCaregiverLink link)): 선택한 환자·보호자 연결 해제를 요청할 콜백.
  // - text (_LinkPatientCaregiverText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _LinkListCard 인스턴스.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 연동된 환자 또는 보호자 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 연동된 환자 또는 보호자 목록에 쓰는 위젯 트리.
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
      // Function Name: build.separatorBuilder callback
      // Description: Separates adjacent entries in the list of linked patients or caregivers using the declared spacing or divider.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // - index (int): Zero-based position of the target medication, photo, or row.
      // Returns: Widget subtree for the described layout or fallback.
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      // 함수이름: build.itemBuilder callback
      // 함수역할: 연동된 환자 또는 보호자 목록에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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
          // 함수이름: build.onChatRequested callback
          // 함수역할: 연동된 환자 또는 보호자 목록에서 캡처된 작업 `onChatRequested(link)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onChatRequested: isEnabled ? () => onChatRequested(link) : null,
          onPatientMedicationRequested: isEnabled
              // 함수이름: build.onPatientMedicationRequested callback
              // 함수역할: 연동된 환자 또는 보호자 목록에서 캡처된 작업 `onPatientMedicationRequested(link)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              ? () => onPatientMedicationRequested(link)
              : null,
          onPatientLabelRequested:
              isEnabled && link.caregiverHash == currentUserHash
              // 함수이름: build.onPatientLabelRequested callback
              // 함수역할: 연동된 환자 또는 보호자 목록에서 캡처된 작업 `onPatientLabelRequested(link)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              ? () => onPatientLabelRequested(link)
              : null,
          // Function Name: build.onUnlinkRequested callback
          // Description: Connects the list of linked patients or caregivers to the captured operation `onUnlinkRequested(link)`.
          // Parameters:
          // - None.
          // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
          onUnlinkRequested: isEnabled ? () => onUnlinkRequested(link) : null,
          text: text,
        );
      },
    );
  }
}

// 클래스명: _LinkedUserTile
// 역할: 연동 사용자 별칭·새 메시지·복약·연결 해제 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 연동 사용자 별칭·새 메시지·복약·연결 해제 명령 위젯을 구성한다.
// 속성:
// - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
// - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
// - patientLabel (String?): 환자 식별에 사용할 별칭.
// - showChatAction (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
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

  // 함수이름: _LinkedUserTile
  // 함수역할: 연동 사용자 별칭·새 메시지·복약·연결 해제 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - link (PatientCaregiverLink): 환자·보호자 연결과 권한 상태.
  // - currentUserHash (String): 현재 작업의 계정 범위를 정하는 사용자 해시.
  // - patientLabel (String?): 환자 식별에 사용할 별칭.
  // - showChatAction (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
  // - isChatAvailable (bool): 근처 약국 또는 연동 복약 채팅 기능의 노출·사용 상태.
  // - onChatRequested (VoidCallback?): 연동 사용자와의 복약 대화를 여는 콜백.
  // - onPatientMedicationRequested (VoidCallback?): 연동 환자의 오늘 복약 상태를 여는 콜백.
  // - onPatientLabelRequested (VoidCallback?): 연동 환자의 표시 별칭을 수정할 콜백.
  // - onUnlinkRequested (VoidCallback?): 선택한 환자·보호자 연결 해제를 요청할 콜백.
  // - text (_LinkPatientCaregiverText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _LinkedUserTile 인스턴스.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 연동 사용자 별칭·새 메시지·복약·연결 해제 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 연동 사용자 별칭·새 메시지·복약·연결 해제 명령에 쓰는 위젯 트리.
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

  // Function Name: _canOpenPatientMedication
  // Description: Checks that the current user is the caregiver of an active link with a nonempty patient hash.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get _canOpenPatientMedication {
    return link.linkStatus &&
        link.caregiverHash == currentUserHash &&
        link.patientHash.trim().isNotEmpty;
  }
}

// 클래스명: _LinkedIdentityField
// 역할: 연동 사용자 식별 표시와 별칭 편집을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 연동 사용자 식별 표시와 별칭 편집 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
class _LinkedIdentityField extends StatelessWidget {
  final String label;
  final String value;

  // 함수이름: _LinkedIdentityField
  // 함수역할: 연동 사용자 식별 표시와 별칭 편집에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 입력 설정이 반영된 _LinkedIdentityField 인스턴스.
  const _LinkedIdentityField({required this.label, required this.value});

  // Function Name: build
  // Description: Renders a linked-user identity display with alias editing from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a linked-user identity display with alias editing.
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

// Function Name: _inputDecoration
// Description: Provides consistent filled, normal-border, and focused-border styling for link-code input.
// Parameters:
// - labelText (String): Wording identifying a field, choice, or action.
// - hintText (String): Example or guidance shown before input.
// Returns: InputDecoration: Input decoration with filled background and normal/focused borders.
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

// 함수이름: _displayHash
// 함수역할: 식별 문자열 공백을 제거하고 비어 있으면 지정한 대체 표시를 사용한다.
// 매개변수:
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - fallback (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _displayHash(String value, String fallback) {
  final displayValue = value.trim();
  if (displayValue.isEmpty) {
    return fallback;
  }
  return displayValue;
}

// 클래스명: _LinkPatientCaregiverText
// 역할: 환자 코드 발급·등록과 환자·보호자 연결 관리에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 환자 코드 발급·등록과 환자·보호자 연결 관리에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
class _LinkPatientCaregiverText {
  final bool isEnglish;

  // 함수이름: _LinkPatientCaregiverText
  // 함수역할: 환자 코드 발급·등록과 환자·보호자 연결 관리에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _LinkPatientCaregiverText 인스턴스.
  const _LinkPatientCaregiverText(String language)
    : isEnglish = language == 'en';

  // 함수이름: close
  // 함수역할: 현재 언어와 입력값에 맞춰 "Close" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get close => isEnglish ? 'Close' : '닫기';
  // 함수이름: screenTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자/보호자 연동하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get screenTitle =>
      isEnglish ? 'Link Patient/Caregiver' : '환자/보호자 연동하기';
  // 함수이름: loadingLinks
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동 정보를 불러오는 중입니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadingLinks =>
      isEnglish ? 'Loading linked accounts.' : '연동 정보를 불러오는 중입니다.';
  // 함수이름: noSavedLinks
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장된 연동정보가 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noSavedLinks =>
      isEnglish ? 'No linked accounts yet.' : '저장된 연동정보가 없습니다.';
  // 함수이름: linkCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count linked account${count == 1 ?" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String linkCount(int count) => isEnglish
      ? '$count linked account${count == 1 ? '' : 's'}.'
      : '총 $count개의 연동이 있습니다.';
  // 함수이름: codeGenerated
  // 함수역할: 현재 언어와 입력값에 맞춰 "보호자에게 공유할 연동 코드를 생성했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get codeGenerated => isEnglish
      ? 'Created a link code to share with a caregiver.'
      : '보호자에게 공유할 연동 코드를 생성했습니다.';
  // 함수이름: enterPatientCode
  // 함수역할: 현재 언어와 입력값에 맞춰 "등록할 환자 연동 코드를 입력해 주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get enterPatientCode =>
      isEnglish ? 'Enter the patient link code.' : '등록할 환자 연동 코드를 입력해 주세요.';
  // 함수이름: linkRegistered
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자-보호자 연동을 등록했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get linkRegistered => isEnglish
      ? 'Patient and caregiver are now linked.'
      : '환자-보호자 연동을 등록했습니다.';
  // 함수이름: missingLinkId
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동 식별자가 없어 해제할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get missingLinkId => isEnglish
      ? 'This link cannot be removed because its identifier is missing.'
      : '연동 식별자가 없어 해제할 수 없습니다.';
  // 함수이름: linkRemoved
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자-보호자 연동을 해제했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get linkRemoved =>
      isEnglish ? 'Patient and caregiver link removed.' : '환자-보호자 연동을 해제했습니다.';
  // 함수이름: linkedPatientOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동된 환자의 복약 정보만 확인할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get linkedPatientOnly => isEnglish
      ? 'You can only view medication information for a linked patient.'
      : '연동된 환자의 복약 정보만 확인할 수 있습니다.';
  // 함수이름: patientLabelTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 표시 이름" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientLabelTitle =>
      isEnglish ? 'Patient display name' : '환자 표시 이름';
  // 함수이름: patientLabelHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "예: 어머니, 아버지" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientLabelHint =>
      isEnglish ? 'Example: Mom, Dad' : '예: 어머니, 아버지';
  // 함수이름: patientLabelHelper
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 이름은 보호자 계정에 동기화됩니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientLabelHelper => isEnglish
      ? 'This name is synced to your caregiver account.'
      : '이 이름은 보호자 계정에 동기화됩니다.';
  // 함수이름: missingAliasLinkId
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동 식별자가 없어 환자 표시 이름을 저장할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get missingAliasLinkId => isEnglish
      ? 'This patient name cannot be saved because the link identifier is missing.'
      : '연동 식별자가 없어 환자 표시 이름을 저장할 수 없습니다.';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';
  // 함수이름: save
  // 함수역할: 현재 언어와 입력값에 맞춰 "Save" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get save => isEnglish ? 'Save' : '저장';
  // 함수이름: patientLabelSaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "$label 표시 이름을 저장했습니다." 문구를 제공한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String patientLabelSaved(String label) =>
      isEnglish ? 'Saved the display name $label.' : '$label 표시 이름을 저장했습니다.';
  // 함수이름: patientPeer
  // 함수역할: 현재 언어와 입력값에 맞춰 "Patient" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientPeer => isEnglish ? 'Patient' : '환자';
  // 함수이름: caregiverPeer
  // 함수역할: 현재 언어와 입력값에 맞춰 "보호자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caregiverPeer => isEnglish ? 'Caregiver' : '보호자';
  // 함수이름: generatePatientCode
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 코드 생성" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get generatePatientCode =>
      isEnglish ? 'Create patient code' : '환자 코드 생성';
  // 함수이름: patientRole
  // 함수역할: 현재 언어와 입력값에 맞춰 "약을 복용하는 환자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientRole =>
      isEnglish ? 'Patient taking medication' : '약을 복용하는 환자';
  // 함수이름: generatePatientCodeSemantic
  // 함수역할: 현재 언어와 입력값에 맞춰 "약을 복용하는 환자입니다. 보호자에게 전달할 연동 코드를 만듭니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get generatePatientCodeSemantic => isEnglish
      ? 'Create a patient link code to share with a caregiver.'
      : '약을 복용하는 환자입니다. 보호자에게 전달할 연동 코드를 만듭니다.';
  // 함수이름: registerPatient
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 관리 등록" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get registerPatient => isEnglish ? 'Register patient' : '환자 관리 등록';
  // 함수이름: caregiverRole
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약을 확인하는 보호자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caregiverRole =>
      isEnglish ? 'Caregiver checking medication' : '복약을 확인하는 보호자';
  // 함수이름: registerPatientSemantic
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약을 확인하는 보호자입니다. 환자에게 받은 연동 코드를 등록합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get registerPatientSemantic => isEnglish
      ? 'Register the link code received from a patient.'
      : '복약을 확인하는 보호자입니다. 환자에게 받은 연동 코드를 등록합니다.';
  // 함수이름: patientCodeLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 코드" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientCodeLabel => isEnglish ? 'Patient code' : '환자 코드';
  // 함수이름: register
  // 함수역할: 현재 언어와 입력값에 맞춰 "등록하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get register => isEnglish ? 'Register' : '등록하기';
  // 함수이름: invalidPatientCode
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 코드는 영문과 숫자 8자리로 입력해 주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidPatientCode => isEnglish
      ? 'Enter an 8-character code using letters and numbers.'
      : '환자 코드는 영문과 숫자 8자리로 입력해 주세요.';
  // 함수이름: patientCodeDialogTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 코드 생성" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientCodeDialogTitle => isEnglish ? 'Patient code' : '환자 코드 생성';
  // 함수이름: codeCopied
  // 함수역할: 현재 언어와 입력값에 맞춰 "코드를 복사했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get codeCopied => isEnglish ? 'Code copied.' : '코드를 복사했습니다.';
  // 함수이름: copyHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "(코드를 클릭하면 복사됩니다)" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get copyHint =>
      isEnglish ? '(Tap the code to copy)' : '(코드를 클릭하면 복사됩니다)';
  // 함수이름: codeInstruction
  // 함수역할: 현재 언어와 입력값에 맞춰 "해당 코드를 보호자 휴대폰에\n등록해주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get codeInstruction => isEnglish
      ? 'Register this code on the caregiver phone.'
      : '해당 코드를 보호자 휴대폰에\n등록해주세요';
  // 함수이름: codeWarning
  // 함수역할: 현재 언어와 입력값에 맞춰 "해당 코드를 보호자 외\n다른 사람과 공유하지 마세요!" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get codeWarning => isEnglish
      ? 'Share this code only with your caregiver.'
      : '해당 코드를 보호자 외\n다른 사람과 공유하지 마세요!';
  // 함수이름: remainingTime
  // 함수역할: 현재 언어와 입력값에 맞춰 "남은 시간:" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get remainingTime => isEnglish ? 'Time left: ' : '남은 시간: ';
  // 함수이름: linkInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "연동 정보" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get linkInformation => isEnglish ? 'Linked account' : '연동 정보';
  // 함수이름: chatUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 복용 중인 약이 없어 채팅을 시작할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get chatUnavailable => isEnglish
      ? 'Chat is unavailable because the patient has no active medication.'
      : '현재 복용 중인 약이 없어 채팅을 시작할 수 없습니다.';
  // 함수이름: medicationChat
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 대화" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationChat => isEnglish ? 'Medication chat' : '복약 대화';
  // 함수이름: editPatientLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 표시 이름 수정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get editPatientLabel =>
      isEnglish ? 'Edit patient display name' : '환자 표시 이름 수정';
  // 함수이름: openPatientMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 복약 정보 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openPatientMedication =>
      isEnglish ? 'View patient medication' : '환자 복약 정보 확인';
  // 함수이름: patientHash
  // 함수역할: 현재 언어와 입력값에 맞춰 "환자 해시" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get patientHash => isEnglish ? 'Patient ID' : '환자 해시';
  // 함수이름: caregiverHash
  // 함수역할: 현재 언어와 입력값에 맞춰 "보호자 해시" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caregiverHash => isEnglish ? 'Caregiver ID' : '보호자 해시';
  // 함수이름: delete
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get delete => isEnglish ? 'Remove link' : '삭제하기';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
}
