# 사용설명서 출처와 검수 범위

- 기준: MedBuddy 0.2.3 개발 브랜치, 앱 캡처 빌드 `8bdb0d2` (`3df4dfd` 포함).
- 확인한 변경 기록: `docs/releases/v0.2.2-beta.md`, `docs/releases/v0.2.3-beta.md`와 해당 화면 구현.
- 전체 190쪽, 10개 대섹션, 74개 소섹션, 264개 사진 설명 단계.
- 검수된 0.2.1 전체 설명서의 257단계를 유지·수정하고 7단계를 추가했습니다.
- 최신 캡처 20개를 43단계에 사용했습니다. 나머지 221단계는 조작 위치가 유지된 0.2.1 검수 캡처입니다.

## 최신 화면의 의미

일반 앱·위젯·Android 권한 화면은 Android 16 Pixel 7 에뮬레이터(1080×2400, 글자 배율 1.0)에서 실제 화면을 캡처했습니다. 별도 합성 약 자료를 사용하는 로컬 테스트 계정이며 실제 사용자 의료자료가 아닙니다.
OCR 수정창·알약 저장 전 수정창·만료 코드 화면은 별도의 Android 15(API 35) 에뮬레이터 `MedBuddy_Pixel8_API35_WidgetCheck`에서 현재 제품 화면 구성 요소를 예시 값으로 연 것입니다. 이 환경은 네트워크를 끈 읽기 전용 테스트 환경입니다. 외부 OCR·AI 호출, 실제 코드 발급·연동, 약 저장까지 성공했다는 증거가 아닙니다.
수동 등록은 선택 방법을 보여 주는 미저장 입력폼입니다. 복약함의 주간약은 별도의 예시 자료이며 앞의 수동 등록을 완료한 결과가 아닙니다. 위젯의 전송 대기 화면과 서버 저장 완료 화면은 구분했습니다.
상태·탐색 막대만 자르고 화면 전체를 배치했으며, 검은 테두리와 번호가 있는 빨간 표시를 문서에 덧붙였습니다. 화면 내용을 합성하거나 실제 UI 대신 그리지 않았습니다.

## 재사용 화면

기존 0.2.1 캡처는 기존 승인된 전체 설명서와 캡처 목록의 SHA-256을 대조했습니다. 과거 날짜·테스트 약·일부 문구가 남은 캡처를 최신 촬영으로 표시하지 않습니다. 보호자 확대 위젯 등 변경되지 않은 조작 화면을 포함합니다.
기준 원고 SHA-256: `e49f7ee54dacce224a167845472867260e2edbec6b8b1acae5678c1a3fe407a7`

## 재현 및 검수

원고·수정 목록·캡처 승인 해시·조판 설정·검수 결과는 별도 저작 작업 묶음에 보관합니다. 저장소에는 최종 PDF·Markdown·로고와 이 출처 기록만 제공하며 로컬 DB, 인증 키, 탐색용 캡처를 포함하지 않습니다.
이 기록은 모든 휴대전화에서의 동작 보증이나 실제 복용 여부의 자동 확인을 뜻하지 않습니다.
전체 190쪽을 이미지로 렌더링해 페이지 배치를 확인하고 변경 화면을 확대 검토했습니다. 본문과 Markdown 일치, 내부 링크 182개·책갈피 84개, 전 페이지 버전·쪽수·섹션 바닥글, 목차 배치, 캡처 128개의 원본 해시를 확인했습니다. 조판 겹침·잘림과 깨진 내부 링크는 발견되지 않았습니다.

## 최신 캡처 무결성

파일명은 검수 자료 식별자입니다. 이 표는 별도 캡처 파일 다운로드를 요구하는 본문 링크가 아닙니다.

| 캡처 파일 | SHA-256 |
|---|---|
| `cabinet-next-dose.png` | `9b217e65d55154807a9c7a42722b0553e1e3cfe90174d8a2a60eadfe4dab6796` |
| `exact-alarm-notice.png` | `ff5309aeaadafa5ade59b8b36de3eaea2b23086caa61e33023f5f25d907997f2` |
| `exact-alarm-system.png` | `7d7b5e6394eeee05e7cfa4d9a2e465a1870c62fd544fe69ba6fb9cbdb2e436da` |
| `home-completed.png` | `e3097ad33e88cc2a70f6ff49e736c6381240f1aa43c9ece7c74ff4e347e7c8c9` |
| `home-undo-confirm.png` | `cfd231344293a62d99909125e7ae1f9bfcd3ee2a8b2a9941b40a2fe93a323874` |
| `manual-lower.png` | `30e94fad93d656e62d6e0b929eed5136b73b2cf647304a531a08238d637b7d11` |
| `manual-upper.png` | `c2c025be67e3b3579e9230e17ad7c1a8224bda0e5db98b4f47af2ab0a01f5e03` |
| `manual-weekly-slots.png` | `08b3f8670fab4dc8bf7a722a29833965c816d6c3a0411d8929cb0e5064035e66` |
| `ocr-weekly-editor.png` | `08cdbb536424612e9d77b8ca7fc757c641b0b5bf5e553e8f1a6293e48b0747c5` |
| `patient-code-expired.png` | `c65533182ece78329c36072caa84f1ebb46fe2b2746c831c8eb89001469e8c5c` |
| `patient-home.png` | `b1582c9815d4430e1a89ed8a17ac5eded25029dc18d3072fbf27883981348557` |
| `pill-review.png` | `1ca306b89e750b40f93c0c57c383a62c4b5fb657e0989b132d8bf46e36d5f114` |
| `pill-weekly-period.png` | `d267f5bd36042698f04b11e441d5712b28ca576eb901ddafdcf5db003e89d9ea` |
| `pill-weekly-top.png` | `730b39dd599c13779d0583bad2bdc76a9c6935fc0867c2467daeeff2cd46bec0` |
| `settings-display.png` | `64e0ecc4d4734217578b503076e47999e6725b9a35da3b85997da6a5b7ef4f28` |
| `settings-overview.png` | `bbecf3393ee520a4e211d5fc6cc4db91407cbd52a9f07de4c67bff3b3dedb8ab` |
| `widget-compact.png` | `405b0f4e59415d4768e6b85686bd8b7038a90511ec57cdacc2db6062a93c99b8` |
| `widget-completed.png` | `dd20edf924ac85c02d60472fef2b5164309f09f16293da6554bd33c842e648d6` |
| `widget-preview.png` | `a706942d8518856b11c7caabd080e1aed371accb63cab288b996fd099c430c8c` |
| `widget-saved.png` | `795e26d3eb5a1e7ea910541d083dab1ea313d225fd389aa3b6444e372f08aa6b` |
