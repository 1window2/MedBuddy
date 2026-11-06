// 파일명: dose_store_open_gate.dart
// 역할: 같은 프로세스의 Flutter 엔진들이 복약 저장소를 한 번에 하나씩 열게 한다.
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

// 클래스명: DoseStoreOpenGate
// 역할: 앱과 WorkManager 엔진의 저장소 열기가 겹치지 않게 프로세스 전체에서 순서를 맞춘다.
// 주요 책임: sqflite는 먼저 열린 연결을 함께 쓰게 하지만 열기가 끝나기 전에 온 요청에는 새 연결을 만든다.
//   연결이 둘이 되면 엔진들이 나눠 쓰는 DB 스레드 하나에서 잠금을 기다리는 쪽이 잠금을 푸는 쪽의
//   COMMIT까지 막는다. 대기 한도는 기기마다 달라 일반 기기는 2.5초, 측정한 삼성 기기는 130초였다.
//   열기만 차례로 하면 연결이 하나로 유지되어 이후 작업은 sqflite가 트랜잭션 단위로 줄을 세운다.
// 속성: register/lookup/remove - 프로세스 공용 이름 등록부, pollInterval - 재시도 간격,
//       waitLimit - 앞선 엔진을 기다리는 한도.
class DoseStoreOpenGate {
  static const _portName = 'medbuddy_dose_store_open_gate';

  final bool Function(SendPort port, String name) register;
  final SendPort? Function(String name) lookup;
  final bool Function(String name) remove;
  final Duration pollInterval;
  final Duration waitLimit;

  const DoseStoreOpenGate({
    this.register = IsolateNameServer.registerPortWithName,
    this.lookup = IsolateNameServer.lookupPortByName,
    this.remove = IsolateNameServer.removePortNameMapping,
    this.pollInterval = const Duration(milliseconds: 20),
    this.waitLimit = const Duration(seconds: 5),
  });

  // 함수이름: run
  // 함수역할: 문을 차지한 동안 작업을 실행하고, 성공·실패와 관계없이 다음 엔진에 넘긴다.
  //   이름 등록은 프로세스 전체에서 한 엔진만 성공하므로 엔진 사이의 잠금으로 쓸 수 있다.
  // 매개변수: action - 저장소를 여는 작업. 반환값: action의 결과.
  Future<T> run<T>(Future<T> Function() action) async {
    final port = ReceivePort();
    final waited = Stopwatch()..start();
    while (!register(port.sendPort, _portName)) {
      if (waited.elapsed >= waitLimit) {
        // 열던 엔진이 종료되면 이름이 남는다. 이 저장소를 영영 못 여는 것보다 넘겨받는 편이 낫다.
        remove(_portName);
        waited.reset();
        continue;
      }
      await Future<void>.delayed(pollInterval);
    }
    try {
      return await action();
    } finally {
      // 한도를 넘겨 문을 넘겨받은 엔진의 등록은 지우지 않는다.
      if (lookup(_portName) == port.sendPort) remove(_portName);
      port.close();
    }
  }
}
