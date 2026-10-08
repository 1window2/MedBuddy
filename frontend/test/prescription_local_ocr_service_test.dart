// 파일명: prescription_local_ocr_service_test.dart
// 역할: 로컬 OCR 개인정보 탐지와 식별자 마스킹을 검증한다.
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image_library;
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';

// 클래스명: _FakeTextRecognizer
// 역할: ML Kit 네이티브 채널 없이 미리 정한 OCR 줄을 돌려주는 인식기 대역이다.
// 주요 책임:
// - recognizeAndMask가 받은 인식 결과만으로 전송 텍스트와 미리보기 영역을 만드는지 확인하게 한다.
// 속성:
// - recognizedText (RecognizedText): processImage가 그대로 돌려줄 인식 결과
// - closed (bool): close 호출 여부
class _FakeTextRecognizer implements TextRecognizer {
  final RecognizedText recognizedText;
  bool closed = false;

  // 함수이름: _FakeTextRecognizer
  // 함수역할: 돌려줄 인식 결과를 보관한다.
  // 매개변수:
  // - recognizedText (RecognizedText): processImage가 돌려줄 인식 결과
  // 반환값:
  // - _FakeTextRecognizer: 초기화된 인스턴스.
  _FakeTextRecognizer(this.recognizedText);

  @override
  TextRecognitionScript get script => TextRecognitionScript.korean;

  @override
  String get id => 'fake-text-recognizer';

  // 함수이름: processImage
  // 함수역할: 입력 이미지와 무관하게 미리 정한 인식 결과를 돌려준다.
  // 매개변수:
  // - inputImage (InputImage): 사용하지 않는 입력 이미지
  // 반환값:
  // - Future<RecognizedText>: 보관한 인식 결과.
  @override
  Future<RecognizedText> processImage(InputImage inputImage) async {
    return recognizedText;
  }

  // 함수이름: close
  // 함수역할: 자원 해제 요청을 기록한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 기록 후 완료.
  @override
  Future<void> close() async {
    closed = true;
  }
}

// 함수이름: _recognizedTextFromBlocks
// 함수역할: 블록별 줄 문구 목록을 위에서 아래로 20픽셀 간격의 경계 상자를 가진 ML Kit 인식 결과로 만든다.
// 매개변수:
// - blocks (List<List<String>>): 블록마다 인식된 줄 문구
// 반환값:
// - RecognizedText: 줄마다 양의 크기 경계 상자를 가진 인식 결과.
RecognizedText _recognizedTextFromBlocks(List<List<String>> blocks) {
  var lineIndex = 0;
  final textBlocks = <TextBlock>[];
  for (final blockLines in blocks) {
    final lines = <TextLine>[];
    for (final text in blockLines) {
      final top = 4.0 + lineIndex * 20;
      lines.add(
        TextLine(
          text: text,
          elements: const [],
          boundingBox: Rect.fromLTRB(10, top, 190, top + 16),
          recognizedLanguages: const ['ko'],
          cornerPoints: const <Point<int>>[],
          confidence: null,
          angle: null,
        ),
      );
      lineIndex += 1;
    }
    textBlocks.add(
      TextBlock(
        text: blockLines.join('\n'),
        lines: lines,
        boundingBox: const Rect.fromLTRB(10, 0, 190, 10),
        recognizedLanguages: const ['ko'],
        cornerPoints: const <Point<int>>[],
      ),
    );
  }
  return RecognizedText(
    text: [for (final block in blocks) ...block].join('\n'),
    blocks: textBlocks,
  );
}

// 함수이름: _writeBlankImage
// 함수역할: recognizeAndMask가 이미지 크기를 읽을 수 있도록 빈 PNG를 임시 폴더에 만들고 사례 종료 시 지운다.
// 매개변수:
// - height (int): 만들 이미지의 세로 픽셀 수
// 반환값:
// - Future<String>: 만든 PNG 파일 경로.
Future<String> _writeBlankImage({int height = 2000}) async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'medbuddy-local-ocr-',
  );
  // 함수이름: addTearDown 콜백
  // 함수역할: 실패 경로를 포함해 사례 종료 후 임시 이미지 폴더를 정리한다.
  // 매개변수: 없음. 반환값: 임시 파일 정리 완료.
  addTearDown(() => temporaryDirectory.delete(recursive: true));
  final file = File('${temporaryDirectory.path}/prescription.png');
  await file.writeAsBytes(
    image_library.encodePng(image_library.Image(width: 200, height: height)),
  );
  return file.path;
}

// 함수이름: main
// 함수역할:
// - 로컬 OCR 개인정보 탐지와 식별자 마스킹 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  const filter = PrescriptionPrivacyFilter();

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 개인정보 라벨과 직접 식별자를 민감정보로 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('개인정보 라벨과 직접 식별자를 민감정보로 판별한다', () {
    expect(filter.containsSensitiveInformation('환자명 홍길동'), isTrue);
    expect(filter.containsSensitiveInformation('주민번호 900101-1234567'), isTrue);
    expect(filter.containsSensitiveInformation('연락처 010-1234-5678'), isTrue);
    expect(filter.containsSensitiveInformation('메일 user@example.com'), isTrue);
    expect(filter.containsSensitiveInformation('환자 정보'), isTrue);
    expect(filter.containsSensitiveInformation('(만 25세 / 남)'), isTrue);
    expect(filter.containsSensitiveInformation('조제일자 2026-07-29'), isFalse);
    expect(filter.containsSensitiveInformation('아스피린 1정 1일 2회'), isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 개인정보 라벨만 있는 경우 다음 OCR 줄도 마스킹한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('개인정보 라벨만 있는 경우 다음 OCR 줄도 마스킹한다', () {
    expect(filter.shouldMaskFollowingLine('환자명'), isTrue);
    expect(filter.shouldMaskFollowingLine('주소 :'), isTrue);
    expect(filter.shouldMaskFollowingLine('환자명 홍길동'), isFalse);
    expect(filter.shouldMaskFollowingLine('약품명'), isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복약 문구에 섞인 직접 식별자는 원문을 남기지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  // 함수이름: 세로로 나열된 개인정보 라벨 가리기 테스트
  // 함수역할: 라벨만 있는 줄이 연속되면 그 수만큼 뒤따르는 값 줄을 모두 가리고, 그 뒤의 약 정보는 남기는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('라벨이 세로로 나열되면 뒤따르는 값 줄을 모두 가린다', () {
    const filter = PrescriptionPrivacyFilter();
    expect(
      filter.sensitiveLineFlags([
        '환자명',
        '주소',
        '홍길동',
        '서울시 마포구 와우산로 94',
        '타이레놀정 500mg 1정 1일 3회',
      ]),
      [true, true, true, true, false],
    );
    expect(
      filter.sensitiveLineFlags(['환자명', '홍길동', '아스피린 100mg']),
      [true, true, false],
    );
  });

  // 함수이름: 인쇄 형식별 나이·성별·주민번호 판별 테스트
  // 함수역할: 순서와 구분 기호가 다른 나이·성별 표기와 가려진 주민등록번호를 민감정보로 보고, 약 이름의 "서방성 명…"은 지우지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('순서가 다른 나이·성별과 가려진 주민번호도 민감정보로 판별한다', () {
    const filter = PrescriptionPrivacyFilter();
    for (final text in const [
      '홍길동 (남/75세)',
      '75세(남)',
      '김영희 여 68세',
      '900101-1******',
      '900101–1234567',
    ]) {
      expect(filter.containsSensitiveInformation(text), isTrue, reason: text);
    }
    for (final text in const [
      '메트포르민 서방성 명일 복용',
      '아세트아미노펜 500mg 1일 3회 5일분',
      '남은 약은 냉장 보관',
    ]) {
      expect(filter.containsSensitiveInformation(text), isFalse, reason: text);
    }
    expect(
      filter.maskInlineIdentifiers('보호자 900101-1****** 확인'),
      '보호자 [주민번호 제거] 확인',
    );
  });

  test('복약 문구에 섞인 직접 식별자는 원문을 남기지 않는다', () {
    final masked = filter.maskInlineIdentifiers(
      '문의 010-1234-5678, user@example.com, 900101-1234567',
    );

    expect(masked, isNot(contains('010-1234-5678')));
    expect(masked, isNot(contains('user@example.com')));
    expect(masked, isNot(contains('900101-1234567')));
    expect(masked, contains('[연락처 제거]'));
    expect(masked, contains('[이메일 제거]'));
    expect(masked, contains('[주민번호 제거]'));
  });

  // 함수이름: 개인정보가 가려져야 하는 라벨 배치 테스트
  // 함수역할: 한 줄에 라벨이 여럿이거나, 나이·성별 라벨이 섞였거나, 수진자 라벨을 쓴 배치에서 환자 값 줄이 모두 가려지고 뒤따르는 약 행은 남는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('라벨 배치가 달라도 환자 값 줄을 가리고 약 행은 남긴다', () {
    const cases = <(List<String>, List<bool>)>[
      // 한 줄에 라벨 둘, 값은 줄마다 하나씩.
      (
        ['환자명 주민등록번호', '홍길동', '900101-1234567', '타이레놀정 1정 3회 5일'],
        [true, true, true, false],
      ),
      (
        ['성명 생년월일', '홍길동', '1950.01.02', '타이레놀정'],
        [true, true, true, false],
      ),
      (
        ['환자명/주민등록번호', '홍길동', '900101-1******', '뮤코펙트정'],
        [true, true, true, false],
      ),
      (
        ['성명 · 생년월일 :', '홍길동', '1950년 1월 2일', '타이레놀정 500mg'],
        [true, true, true, false],
      ),
      // 한 줄에 라벨 둘, 값도 한 줄에 붙어 인식된 경우.
      (
        ['성명 주민등록번호', '홍길동 900101-1234567', '뮤코펙트정'],
        [true, true, false],
      ),
      (
        ['성명 생년월일', '홍길동 1950.01.02', '뮤코펙트정'],
        [true, true, false],
      ),
      (
        ['성명 생년월일 전화번호', '홍길동 1950-01-02 010-1234-5678', '뮤코펙트정'],
        [true, true, false],
      ),
      // 이름과 연락처만 붙고 주소가 다음 줄로 넘어간 경우에도 주소를 가린다.
      (
        ['성명 전화번호 주소', '홍길동 010-1234-5678', '서울시 마포구 와우산로 94', '뮤코펙트정'],
        [true, true, true, false],
      ),
      // 나이·성별 라벨이 개인정보 라벨 사이에 섞인 세로 표.
      (
        ['성명', '연령', '홍길동', '75', '아스피린'],
        [true, true, true, true, false],
      ),
      (
        ['환자명', '성별', '나이', '주소', '홍길동', '남', '75', '서울시 마포구 와우산로 94', '타이레놀정'],
        [true, true, true, true, true, true, true, true, false],
      ),
      (
        ['나이', '성명', '75', '홍길동', '아스피린'],
        [true, true, true, true, false],
      ),
      (
        ['환자명', '나이/성별', '홍길동', '75/남', '뮤코펙트정'],
        [true, true, true, true, false],
      ),
      // 나이·성별 라벨이 개인정보 라벨과 한 줄에 있는 머리행.
      (
        ['성명 성별 연령', '홍길동', '남', '75', '아스피린'],
        [true, true, true, true, false],
      ),
      (
        ['성명 성별 연령', '홍길동 남 75', '뮤코펙트정'],
        [true, true, false],
      ),
      (
        ['성명 연령', '홍길동 75', '뮤코펙트정'],
        [true, true, false],
      ),
      (
        ['성명 성별/나이', '홍길동 (남/75세)', '뮤코펙트정'],
        [true, true, false],
      ),
      // 수진자 라벨.
      (
        ['수진자 홍길동', '교부번호 2026-00012'],
        [true, false],
      ),
      (
        ['수진자', '홍길동', '아스피린 100mg'],
        [true, true, false],
      ),
      (
        ['수진자명 :', '홍길동', '타이레놀정'],
        [true, true, false],
      ),
      // "수진자 성명"은 라벨 하나이므로 값도 한 줄만 가린다.
      (
        ['수진자 성명', '홍길동', '타이레놀정'],
        [true, true, false],
      ),
      (
        ['수진자 성명 주민등록번호', '홍길동', '900101-1******', '타이레놀정'],
        [true, true, true, false],
      ),
      // 값 줄에 붙은 부가 표기(나이, HP)를 다른 라벨의 값으로 세지 않는다.
      (
        ['주민등록번호 성명', '900101-1234567 (만 75세)', '홍길동', '뮤코펙트정'],
        [true, true, true, false],
      ),
      (
        ['성명 전화번호 주소', '홍길동', 'HP 010-1234-5678', '서울시 마포구 와우산로 94', '뮤코펙트정'],
        [true, true, true, true, false],
      ),
      (
        ['성명 주소 보험번호', '홍길동', '서울시 마포구 와우산로 94', '1234567890', '뮤코펙트정'],
        [true, true, true, true, false],
      ),
      (
        ['성명', '성별', '주소', '홍길동 (남/75세)', '서울시 마포구 와우산로 94', '뮤코펙트정'],
        [true, true, true, true, true, false],
      ),
      // "정"으로 끝나는 이름과 숫자가 든 주소는 약 행으로 보지 않는다.
      (
        ['성명', '김수정', '타이레놀정'],
        [true, true, false],
      ),
      (
        ['성명', '주소', '박은정', '경기도 성남시 분당구 정자일로 95 101동 1203호', '게보린정'],
        [true, true, true, true, false],
      ),
      // 라벨과 값이 번갈아 나오는 기존 배치는 그대로다.
      (
        ['성명', '홍길동', '주민등록번호', '900101-1234567', '주소', '서울시 마포구 와우산로 94', '타이레놀정'],
        [true, true, true, true, true, true, false],
      ),
    ];

    for (final (lines, expected) in cases) {
      expect(filter.sensitiveLineFlags(lines), expected, reason: '$lines');
    }
    expect(filter.containsSensitiveInformation('수진자 홍길동'), isTrue);
    expect(filter.containsSensitiveInformation('수진자명: 홍길동'), isTrue);
    expect(filter.shouldMaskFollowingLine('환자명 주민등록번호'), isTrue);
    expect(filter.shouldMaskFollowingLine('수진자'), isTrue);
  });

  // 함수이름: 약 행이 가려지지 않아야 하는 배치 테스트
  // 함수역할: 값 줄 수가 라벨 수보다 적거나 표 머리행·약 행이 바로 이어지는 배치에서 약 행이 개인정보로 잘못 가려지지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('약 행과 약 표 머리행은 개인정보로 가리지 않는다', () {
    const cases = <(List<String>, List<bool>)>[
      // 라벨 하나와 값 하나 바로 뒤의 약 행.
      (
        ['환자명', '홍길동', '타이레놀정'],
        [true, true, false],
      ),
      (
        ['성명 :', '홍길동', '뮤코펙트정', '1', '3', '5'],
        [true, true, false, false, false, false],
      ),
      (
        ['환자명 홍길동', '타이레놀정'],
        [true, false],
      ),
      (
        ['수진자 홍길동', '아스피린'],
        [true, false],
      ),
      // 약 표 머리행은 라벨 줄이 아니다.
      (
        ['약품명 투약량 횟수 일수', '타이레놀정 500mg', '1', '3', '5'],
        [false, false, false, false, false],
      ),
      (
        ['처방 의약품의 명칭', '1회 투약량', '1일 투여횟수', '총 투약일수', '뮤코펙트정'],
        [false, false, false, false, false],
      ),
      (
        ['환자명', '홍길동', '약품명 투약량 횟수 일수', '뮤코펙트정', '1', '3', '5'],
        [true, true, false, false, false, false, false],
      ),
      // 값이 인식되지 않아 라벨 바로 뒤에 약 행이 오면 약 행을 값으로 보지 않는다.
      (
        ['환자명', '타이레놀정 500mg 1정 3회 5일', '뮤코펙트정'],
        [true, false, false],
      ),
      (
        ['환자명 주민등록번호', '아모크라정 625mg', '뮤코펙트정'],
        [true, false, false],
      ),
      (
        ['환자명', '주민등록번호', '주소', '홍길동', '900101-1******', '타이레놀정500mg', '뮤코펙트정'],
        [true, true, true, true, true, false, false],
      ),
      (
        ['성명', '연령', '홍길동', '코대원포르테시럽', '뮤코펙트정'],
        [true, true, true, false, false],
      ),
      (
        ['성명 주소', '홍길동', '세파클러캡슐 250mg 1캡슐씩 3회', '뮤코펙트정'],
        [true, true, false, false],
      ),
      // 이름 줄에 나이·성별이 함께 적혀 있으면 나이·성별 라벨 몫까지 한 줄로 끝난다.
      (
        ['성명', '성별', '홍길동 (남/75세)', '타이레놀정', '뮤코펙트정'],
        [true, true, true, false, false],
      ),
      // 나이·성별 라벨만 있으면 다음 줄을 가리지 않는다.
      (
        ['연령', '75', '아스피린'],
        [false, false, false],
      ),
      (
        ['성별/나이', '남/75', '아스피린'],
        [false, false, false],
      ),
      // 처방 의료인 줄은 라벨만 있는 줄이 아니므로 다음 줄을 가리지 않는다.
      (
        ['처방 의료인의 성명', '김의사', '타이레놀정'],
        [true, false, false],
      ),
      // 용법 문구.
      (
        ['환자명', '홍길동', '1일 3회 식후 30분', '아세트아미노펜 500mg 1일 3회 5일분'],
        [true, true, false, false],
      ),
    ];

    for (final (lines, expected) in cases) {
      expect(filter.sensitiveLineFlags(lines), expected, reason: '$lines');
    }
    expect(filter.shouldMaskFollowingLine('약품명 투약량 횟수 일수'), isFalse);
    expect(filter.shouldMaskFollowingLine('연령'), isFalse);
    expect(filter.shouldMaskFollowingLine('수진자 홍길동'), isFalse);
  });

  // 함수이름: recognizeAndMask 전송 텍스트 테스트
  // 함수역할: 인식기 대역이 돌려준 줄에서 환자 값 줄과 직접 식별자가 전송 텍스트와 미리보기 영역 문구에 남지 않고, 약 행과 조제일자는 남는지 검증한다.
  // 매개변수: 없음. 반환값: Future<void>; 불일치 시 테스트 실패.
  test('recognizeAndMask는 환자 값 줄을 빼고 약 행만 전송 텍스트에 남긴다', () async {
    final imagePath = await _writeBlankImage();
    final recognizer = _FakeTextRecognizer(
      _recognizedTextFromBlocks(const [
        ['환자명 주민등록번호', '홍길동', '900101-1234567'],
        ['성명', '연령', '김영희', '75'],
        ['수진자 박철수', '  ', '조제일자 2026-07-29'],
        ['약품명 투약량 횟수 일수', '타이레놀정 500mg 1정 3회 5일'],
        ['뮤코펙트정', '문의 010-1234-5678'],
      ]),
    );
    final service = PrescriptionLocalOcrService(textRecognizer: recognizer);

    final result = await service.recognizeAndMask(imagePath);

    expect(
      result.maskedText,
      [
        '조제일자 2026-07-29',
        '약품명 투약량 횟수 일수',
        '타이레놀정 500mg 1정 3회 5일',
        '뮤코펙트정',
      ].join('\n'),
    );
    for (final secret in const [
      '홍길동',
      '김영희',
      '박철수',
      '900101',
      '010-1234-5678',
    ]) {
      expect(result.maskedText, isNot(contains(secret)), reason: secret);
      for (final region in result.regions) {
        expect(region.text, isNot(contains(secret)), reason: secret);
      }
    }
    final sensitiveRegions = result.regions.where(
      // 함수이름: where 콜백
      // 함수역할: 개인정보 마스킹 영역만 고른다.
      // 매개변수: region (RecognizedTextRegion): 검사할 영역. 반환값: 개인정보 영역이면 true.
      (region) => region.isSensitive,
    );
    // 연락처가 섞인 "문의" 줄은 줄 전체가 개인정보 줄로 빠진다.
    expect(sensitiveRegions, hasLength(9));
    expect(
      sensitiveRegions.every(
        // 함수이름: every 콜백
        // 함수역할: 개인정보 영역에 원문이 남지 않았는지 확인한다.
        // 매개변수: region (RecognizedTextRegion): 검사할 영역. 반환값: 문구가 비어 있으면 true.
        (region) => region.text.isEmpty,
      ),
      isTrue,
    );
    expect(
      result.regions
          .where(
            // 함수이름: where 콜백
            // 함수역할: 조제일자 영역만 고른다.
            // 매개변수: region (RecognizedTextRegion): 검사할 영역. 반환값: 날짜 영역이면 true.
            (region) => region.category == 'prescription_date',
          )
          .single
          .text,
      '조제일자 2026-07-29',
    );
    // 첫 줄(4~20px / 2000px)은 0~1000 좌표로 바뀐다.
    expect(result.regions.first.box2d, [2, 50, 10, 950]);

    await service.dispose();
    expect(recognizer.closed, isTrue);
  });

  // 함수이름: recognizeAndMask 개인정보만 인식된 경우 테스트
  // 함수역할: 전송할 수 있는 줄이 하나도 남지 않으면 빈 텍스트를 보내지 않고 오류로 끝나는지 검증한다.
  // 매개변수: 없음. 반환값: Future<void>; 불일치 시 테스트 실패.
  test('recognizeAndMask는 개인정보 외의 줄이 없으면 오류로 끝난다', () async {
    final imagePath = await _writeBlankImage();
    final service = PrescriptionLocalOcrService(
      textRecognizer: _FakeTextRecognizer(
        _recognizedTextFromBlocks(const [
          ['환자명', '홍길동', '주민번호 900101-1234567'],
        ]),
      ),
    );

    await expectLater(
      service.recognizeAndMask(imagePath),
      throwsA(isA<StateError>()),
    );
  });

  // 함수이름: recognizeAndMask 미리보기 영역 상한 테스트
  // 함수역할: 일반 영역이 상한 80개를 채운 뒤에 나온 개인정보 줄도 마스킹 영역으로 남고, 전송 텍스트는 상한과 무관하게 모든 안전한 줄을 담는지 검증한다.
  // 매개변수: 없음. 반환값: Future<void>; 불일치 시 테스트 실패.
  test('recognizeAndMask는 영역 상한을 넘은 뒤의 개인정보 줄도 마스킹 영역으로 남긴다', () async {
    final imagePath = await _writeBlankImage();
    final service = PrescriptionLocalOcrService(
      textRecognizer: _FakeTextRecognizer(
        _recognizedTextFromBlocks([
          [for (var index = 0; index < 85; index += 1) '복약 안내 $index'],
          const ['환자명 홍길동', '보호자 연락처 010-1234-5678'],
        ]),
      ),
    );

    final result = await service.recognizeAndMask(imagePath);

    expect(
      result.regions.where(
        // 함수이름: where 콜백
        // 함수역할: 개인정보가 아닌 일반 인식 영역만 고른다.
        // 매개변수: region (RecognizedTextRegion): 검사할 영역. 반환값: 일반 영역이면 true.
        (region) => !region.isSensitive,
      ),
      hasLength(80),
    );
    expect(
      result.regions.where(
        // 함수이름: where 콜백
        // 함수역할: 개인정보 마스킹 영역만 고른다.
        // 매개변수: region (RecognizedTextRegion): 검사할 영역. 반환값: 개인정보 영역이면 true.
        (region) => region.isSensitive,
      ),
      hasLength(2),
    );
    expect(result.maskedText.split('\n'), hasLength(85));
    expect(result.maskedText, contains('복약 안내 84'));
    expect(result.maskedText, isNot(contains('홍길동')));
  });
}
