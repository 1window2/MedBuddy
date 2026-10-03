// 파일명: medication_loading_tip.dart
// 역할: 처방전 분석 대기 중 일반 복약 팁을 무작위 순서로 표시한다.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: MedicationLoadingTip
// 역할: OCR·API 분석 화면에서 함께 쓰는 복약 팁 표시 영역이다.
// 주요 책임: 중복 없는 무작위 순환과 큰 글씨·화면 읽기 접근성을 제공한다.
// 속성: language는 표시 언어이며 별도 사용자 데이터나 API를 사용하지 않는다.
class MedicationLoadingTip extends StatefulWidget {
  final String language;
  static const rotationInterval = Duration(seconds: 10);

  // 함수이름: MedicationLoadingTip
  // 함수역할: 팁 표시 언어를 받는다. 매개변수: key, language. 반환값: 팁 위젯.
  const MedicationLoadingTip({super.key, required this.language});

  // 함수이름: createState
  // 함수역할: 팁 순서와 타이머를 관리한다. 매개변수: 없음. 반환값: 화면 상태.
  @override
  State<MedicationLoadingTip> createState() => _MedicationLoadingTipState();
}

// 클래스명: _MedicationLoadingTipState
// 역할: 분석 요청과 독립적으로 팁을 순환하고 화면 종료 시 타이머를 해제한다.
// 주요 책임: 모든 팁을 한 번씩 표시한 뒤 다시 섞고 연속 중복은 방지한다.
// 속성: _order는 팁 순서, _position은 현재 위치, _timer는 자동 전환 타이머이다.
class _MedicationLoadingTipState extends State<MedicationLoadingTip>
    with WidgetsBindingObserver {
  final Random _random = Random();
  late List<int> _order;
  int _position = 0;
  Timer? _timer;
  bool _automaticRotation = false;
  AppLifecycleState? _lifecycleState;

  // 일반 안전 안내의 근거와 범위는 docs/MedBuddy - Analysis Loading Tips.md에 기록한다.
  static const _tips = [
    (
      ko: '약의 복용량과 시간을 처방전·약 봉투에서 확인하세요.',
      en: 'Check your prescription or medicine label for the dose and timing.',
    ),
    (
      ko: '복용 중인 약과 건강기능식품 목록을 진료·상담 때 알려주세요.',
      en: 'Share your list of medicines and supplements with your doctor or pharmacist.',
    ),
    (
      ko: '복용 방법이 헷갈리면 임의로 판단하지 말고 약사에게 확인하세요.',
      en: 'If you are unsure how to take a medicine, ask your pharmacist.',
    ),
    (
      ko: '약의 보관 방법은 포장이나 설명서에서 확인하세요.',
      en: 'Check the packaging or leaflet for medicine storage instructions.',
    ),
    (
      ko: '새 약을 받으면 유효기간과 주의사항을 확인하세요.',
      en: 'When you receive a medicine, check its expiry date and warnings.',
    ),
    (
      ko: '인식된 약 이름과 용량이 처방전과 일치하는지 확인하세요.',
      en: 'Check that recognized medicine names and doses match your prescription.',
    ),
    (
      ko: '실제로 복용한 뒤 완료를 기록하면 복약 현황을 확인하기 쉬워요.',
      en: 'Record completion after taking your medicine to keep your medication log accurate.',
    ),
    (
      ko: '알약 사진의 식별 결과는 후보예요. 포장 정보나 약사에게 다시 확인하세요.',
      en: 'Pill photo results are only candidates. Verify them with the packaging or a pharmacist.',
    ),
  ];

  // 함수이름: initState
  // 함수역할: 첫 순서를 섞고 앱 생명주기 감시를 등록한다. 매개변수: 없음. 반환값: 없음.
  @override
  void initState() {
    super.initState();
    _shuffleTips(null);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  // 함수이름: didChangeDependencies
  // 함수역할: 화면 읽기·움직임 감소·비활성 화면에서는 자동 전환을 멈춘다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _automaticRotation =
        !mediaQuery.accessibleNavigation &&
        !mediaQuery.disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    _syncTimer();
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱이 활성 상태일 때만 자동 전환한다. 매개변수: state. 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTimer();
  }

  // 함수이름: _syncTimer
  // 함수역할: 허용된 상태에서만 타이머 한 개를 유지한다. 매개변수: 없음. 반환값: 없음.
  void _syncTimer() {
    final foreground =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    if (!_automaticRotation || !foreground) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(
        MedicationLoadingTip.rotationInterval,
        _onTimer,
      );
    }
  }

  // 함수이름: _onTimer
  // 함수역할: 현재 보이는 분석 화면에서만 다음 팁으로 이동한다.
  // 매개변수: timer는 주기 타이머. 반환값: 없음.
  void _onTimer(Timer timer) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    setState(_selectNextTip);
  }

  // 함수이름: _shuffleTips
  // 함수역할: 모든 팁을 섞고 직전 팁과 새 첫 팁이 같으면 순서를 교환한다.
  // 매개변수: previous는 직전에 표시한 팁 번호. 반환값: 없음.
  void _shuffleTips(int? previous) {
    _order = [for (var i = 0; i < _tips.length; i++) i]..shuffle(_random);
    if (_order.first == previous) {
      final first = _order[0];
      _order[0] = _order[1];
      _order[1] = first;
    }
    _position = 0;
  }

  // 함수이름: _selectNextTip
  // 함수역할: 한 순환 안에서 중복 없이 이동하고 마지막에서 다시 섞는다.
  // 매개변수: 없음. 반환값: 없음.
  void _selectNextTip() {
    if (_position == _order.length - 1) {
      _shuffleTips(_order[_position]);
    } else {
      _position++;
    }
  }

  // 함수이름: _showNextTip
  // 함수역할: 수동으로 다음 팁을 표시하고 새 문장을 읽을 시간을 확보한다.
  // 매개변수: 없음. 반환값: 없음.
  void _showNextTip() {
    setState(_selectNextTip);
    _timer?.cancel();
    _timer = null;
    _syncTimer();
  }

  // 함수이름: dispose
  // 함수역할: 분석 종료·취소 시 타이머와 감시를 해제한다. 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 제목과 팁을 중앙 정렬하고, 전체 길이에 맞는 고정 공간에서 현재 문장만 표시·읽기 대상으로 제공한다.
  // 매개변수: context는 언어·접근성 문맥. 반환값: 제목, 팁, 다음 팁 버튼.
  @override
  Widget build(BuildContext context) {
    final isEnglish = widget.language == 'en';
    final labels = [for (final tip in _tips) isEnglish ? tip.en : tip.ko];
    final selected = _order[_position];
    return Column(
      key: const ValueKey('analysisMedicationTip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 48,
              child: Icon(
                Icons.lightbulb_outline_rounded,
                color: MedBuddyColors.primaryDark,
                size: 24,
              ),
            ),
            Expanded(
              child: Text(
                isEnglish ? 'Medication tip' : '복약 팁',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: MedBuddyColors.primaryDark,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: IconButton(
                key: const ValueKey('nextAnalysisMedicationTip'),
                tooltip: isEnglish ? 'Next tip' : '다음 팁',
                onPressed: _showNextTip,
                icon: const Icon(Icons.arrow_forward_rounded),
                color: MedBuddyColors.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: labels[selected],
          child: ExcludeSemantics(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Visibility(
                    visible: i == selected,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: Text(
                      labels[i],
                      key: i == selected
                          ? const ValueKey('analysisMedicationTipText')
                          : null,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: MedBuddyColors.textBody,
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
}
