// 파일명: dose_store_open_gate_test.dart
// 역할: 앱과 백그라운드 엔진의 복약 저장소 열기가 겹치지 않는지 검증한다.
// 다른 엔진은 만들지 않는다. 두 엔진의 실제 경합은 Android 에뮬레이터에서 따로 확인했다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_store_open_gate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 클래스명: _Registry
// 역할: 프로세스 공용 이름 등록부의 메모리 대역.
// 속성: ports - 이름별 등록 포트, removals - 지운 횟수.
class _Registry {
  final Map<String, SendPort> ports = {};
  int removals = 0;

  // 함수이름: gate
  // 함수역할: 이 등록부를 쓰는 문을 만든다. 매개변수: waitLimit - 대기 한도. 반환값: 문.
  DoseStoreOpenGate gate({Duration waitLimit = const Duration(seconds: 5)}) =>
      DoseStoreOpenGate(
        register: (port, name) {
          if (ports.containsKey(name)) return false;
          ports[name] = port;
          return true;
        },
        lookup: (name) => ports[name],
        remove: (name) {
          removals++;
          return ports.remove(name) != null;
        },
        pollInterval: const Duration(milliseconds: 1),
        waitLimit: waitLimit,
      );
}

// 함수이름: main
// 함수역할: 저장소 열기 순서와 문을 넘기는 경우를 검증한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  sqfliteFfiInit();

  test('opens one at a time on the process-wide registry', () async {
    const gate = DoseStoreOpenGate(pollInterval: Duration(milliseconds: 1));
    final firstMayFinish = Completer<void>();
    var secondStarted = false;

    final first = gate.run(() => firstMayFinish.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = gate.run(() async => secondStarted = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(secondStarted, isFalse);

    firstMayFinish.complete();
    await Future.wait([first, second]);
    expect(secondStarted, isTrue);
  });

  test('a failed open passes the gate to the next caller', () async {
    final registry = _Registry();
    final gate = registry.gate();

    await expectLater(
      gate.run<void>(() async => throw StateError('open failed')),
      throwsStateError,
    );

    expect(registry.ports, isEmpty);
    expect(await gate.run(() async => 'opened'), 'opened');
  });

  test('takes over a gate left behind by an engine that stopped', () async {
    final registry = _Registry();
    final stale = ReceivePort();
    addTearDown(stale.close);
    final gate = registry.gate(waitLimit: const Duration(milliseconds: 10));
    registry.ports['medbuddy_dose_store_open_gate'] = stale.sendPort;

    expect(await gate.run(() async => 'opened'), 'opened');

    expect(registry.ports, isEmpty);
  });

  test('a slow engine keeps the registration of its successor', () async {
    final registry = _Registry();
    final next = ReceivePort();
    addTearDown(next.close);
    final gate = registry.gate();

    await gate.run(() async {
      registry.ports['medbuddy_dose_store_open_gate'] = next.sendPort;
    });

    expect(registry.ports.values, [next.sendPort]);
    expect(registry.removals, 0);
  });

  group('DoseOutboxStore.openWith', () {
    late Directory directory;
    late List<Database> opened;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('dose-open-gate-');
      opened = [];
    });

    tearDown(() async {
      for (final db in opened) {
        await db.close();
      }
      await directory.delete(recursive: true);
    });

    test('a second engine waits until the first finished opening', () async {
      final key = base64Encode(List<int>.filled(32, 7));
      final firstMayFinish = Completer<void>();
      final order = <String>[];
      Future<DoseOutboxStore> open(String name, {Completer<void>? hold}) {
        return DoseOutboxStore.openWith(
          readKey: () async => key,
          writeKey: (_) async {},
          openDatabase: () async {
            order.add('$name start');
            await hold?.future;
            final db = await databaseFactoryFfi.openDatabase(
              '${directory.path}/$name.db',
              options: OpenDatabaseOptions(
                version: 1,
                onCreate: DoseOutboxStore.createSchema,
              ),
            );
            opened.add(db);
            order.add('$name end');
            return db;
          },
          openGate: const DoseStoreOpenGate(
            pollInterval: Duration(milliseconds: 1),
          ),
        );
      }

      final first = open('first', hold: firstMayFinish);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = open('second');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, ['first start']);

      firstMayFinish.complete();
      await Future.wait([first, second]);
      expect(order, [
        'first start',
        'first end',
        'second start',
        'second end',
      ]);
    });
  });
}
