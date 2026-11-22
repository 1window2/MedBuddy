// 선택한 품목의 상세 조회가 이름 검색 없이 제한된 시간 안에 끝나는지 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';

void main() {
  const id = '202001476';
  final details = {
    'item_seq': id,
    'item_name': '선택한 약',
    'manufacturer': '제약회사',
    'efficacy': '효능',
    'usage_method': '사용법',
    'warning': '주의사항',
  };

  test(
    'exact product lookup uses one GET and retains catalog details',
    () async {
      final requests = <http.Request>[];
      final control = CheckMedicationDetail(
        baseUrl: 'https://medbuddy.test/medication',
        client: MockClient((request) async {
          requests.add(request);
          return _response({'success': true, 'data': details});
        }),
      );
      final result = await control.requestCatalogMedicationDetail(' $id ');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/medication/catalog/$id');
      expect(requests.single.body, isEmpty);
      expect(result?.itemSeq, id);
      expect(result?.manufacturer, '제약회사');
      expect(result?.efficacy, '효능');
      expect(result?.usageMethod, '사용법');
      expect(result?.warning, '주의사항');
    },
  );

  test('invalid product codes never make a network request', () async {
    final control = CheckMedicationDetail(
      client: MockClient((_) async {
        fail('Invalid item code reached the network');
      }),
    );
    for (final invalid in ['', '../identify', 'not-a-code', '1' * 33]) {
      expect(await control.requestCatalogMedicationDetail(invalid), isNull);
    }
  });

  for (final entry in <String, Object?>{
    'missing product': null,
    'unexpected list': [details],
    'different product': {...details, 'item_seq': '200000002'},
    'missing product identity': {...details, 'item_seq': ''},
  }.entries) {
    test('${entry.key} never supplies another product detail', () async {
      final control = CheckMedicationDetail(
        client: MockClient(
          (_) async => _response({'success': true, 'data': entry.value}),
        ),
      );
      expect(await control.requestCatalogMedicationDetail(id), isNull);
    });
  }

  test('failed response is passed to the save fallback', () async {
    final control = CheckMedicationDetail(
      client: MockClient(
        (_) async => http.Response('Service unavailable', 503),
      ),
    );
    await expectLater(
      control.requestCatalogMedicationDetail(id),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('catalog lookup cannot hold saving for more than five seconds', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final control = CheckMedicationDetail(
      client: MockClient((_) => gate.future),
    );
    final result = control.requestCatalogMedicationDetail(id);
    final expectation = expectLater(result, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 5));
    await expectation;
    gate.complete(_response({'success': true, 'data': details}));
    await tester.pump();
  });
}

http.Response _response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
