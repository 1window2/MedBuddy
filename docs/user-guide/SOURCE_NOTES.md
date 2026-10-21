# 사용설명서 출처와 검수 범위

- 기준: `beta/v0.2.3`의 2026-10-17 로컬 미커밋 변경 포함 작업본. 정식 출시본을 의미하지 않습니다.
- 전체 216쪽, 10개 대섹션, 83개 소섹션, 303개 사진 설명 단계.
- 직전 212쪽·292단계의 모든 단계 ID와 소섹션, 기존 단계의 순서를 유지·수정하고 11단계를 추가했습니다. 요약본으로 대체하지 않았습니다.
- 이번 최종 갱신에서 실제 앱 화면 28개를 60단계에 반영했습니다. 이 중 27개는 이번에 새로 캡처하고 나머지는 같은 날의 제공 자료에서 재사용했습니다.

## 반영 내용

- 복약 기록: 좌우 날짜 화살표, 중앙 날짜 달력, 상태 건수 옆 정보 버튼, 보호자 읽기 전용 표시.
- 필요시 복용: 기록 화면의 신규 입력 버튼 대신 일정의 동그라미·일괄 체크, 2회부터 횟수 확인, 기존 기록의 연필 정정.
- 환자 필요시 확인 알림: 사용자가 켜고 고른 다음 시각에 한 번만. 보호자 필요시 알림: 끄기·복용 확인 즉시 알림만.
- 보호자 일정의 공통 시간대 배치, 직접 등록·처방 교체의 공통 입력 양식, 변경 시작일과 교체 복용 시작일 구분.
- 상태 배지: 중단 빨강, 교체 파랑, 중단·교체 예정 주황, 기간 종료 회색. 실제 캡처에는 중단·교체가 표시되며 예정·종료는 코드로 확인했습니다.
- CSV의 별도 시작일·종료일과 간략 공유 안내, 홈 준비 점검 바로가기 없음, 설정 분류·소제목 유지.

## 화면과 코드 근거

환자 emulator-5554, 보호자 emulator-5556의 실행 중인 데모 앱에서 PNG와 UI XML을 함께 캡처했습니다. 실제 환자 정보가 아닌 Demo 테스트 약입니다. 약 이름·횟수·기기 시각이 다른 화면은 각각 조작 위치의 예시이며 연속된 복용이나 권장 횟수가 아닙니다. 문서의 날짜·시각 설명은 앱의 한국 시간 기준입니다.
이번 촬영에서는 조회·달력·입력폼·설정창·저장 전 확인창과 Android 공유창을 열었으며 복용 기록·약 정보·알림 설정을 저장하거나 중단·교체를 적용하지 않았습니다. 중단·교체 확인창은 취소로 닫았습니다. 앱/백엔드 수정·빌드·계정 초기화·외부 AI 호출·실제 공유 전송을 하지 않았습니다. 기록된 테스트 약과 횟수는 기존 데모 데이터입니다. 추가 복용 횟수 확인은 제공된 자료를 재사용했습니다. Android 공유창은 현재 UI에서 CSV 공유를 눌러 기간 재조회 후 직접 촬영하고, 앱 선택·전송 없이 뒤로가기로 닫았습니다.
변경되지 않은 0.2.1·0.2.3 검수 화면을 유지했습니다. 이전에 확보한 처방전 수정·알약 검토 등 분리된 제품 위젯 예시도 유지하며 이번의 실제 앱 캡처로 재분류하지 않았습니다. 캡처 내용은 합성하지 않고 시스템 상태·탐색 영역만 잘랐습니다. 빨간 강조 테두리와 번호는 PDF 설명용 표시입니다.
현재 화면·제어 코드의 경로와 SHA-256은 재생성 소스의 `code-evidence.json`에 기록했습니다. 기록 화면, PRN 일정·확인 알림, 보호자 일정·알림 설정, 약 등록·교체, 상태 배지, 홈·환경설정 및 PRN 보호자 이벤트를 대조했습니다.

## 재생성 소스

저장소 반영 파일은 이 폴더의 PDF·README·SOURCE_NOTES 세 파일뿐입니다. 재생성 가능한 전체 원고·캡처·조판 도구·검수 자료는 다음 로컬 작업 폴더에 보관합니다.

```text
C:\Users\LSH\Documents\MedBuddy\work\user-guide-final-20261017
```

- `baseline/`: 직전 212쪽 PDF, 292단계 원고, 출처 및 구조 검수 결과의 고정 사본.
- `updates.json`, `build_guide.py`: 본문 수정과 11개 추가 단계, 캡처 매핑, 전체 재조판 절차.
- `assets/`, `asset-map.json`: 사용 이미지와 XML의 해시 검증 사본. 원본 캡처가 이동해도 이 사본으로 재생성합니다.
- `tooling/`: 사용한 조판·검증 도구의 고정 사본. `content.json`, `provenance.json`: 최종 전체 원고·화면 출처.
- `candidate/`: 산출물과 구조 검수 JSON, `review/`: 전체 PDF 렌더·변경 쪽 확대·캡처 검토 시트.

Windows PowerShell 재생성 명령(앱 빌드나 서버 실행 불필요):

```powershell
$python = 'C:\Users\LSH\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$source = 'C:\Users\LSH\Documents\MedBuddy\work\user-guide-final-20261017\build_guide.py'
& $python -B $source build
& $python -B $source verify
& $python -B $source render
```

NanumBarunGothic·NanumBarunGothicBold 글꼴과 번들 Python의 reportlab·pypdf·Pillow, Poppler가 필요합니다. `build`는 검수 상태를 미확정으로 되돌립니다. 렌더를 실제 검토한 뒤에만 `finalize`를 실행합니다. 스크립트는 저장소에 복사·스테이지·커밋·푸시하지 않습니다.

## 검수

- 216쪽 전체를 Poppler로 렌더링하고 전체 축소 검토와 핵심 변경 화면 확대 검토를 완료했습니다. 잘림·겹침·빈 페이지·이미지 누락을 확인했습니다. 마지막 공유창 교체 후에는 76쪽과 해당 검토 시트만 다시 렌더링·확인하고 나머지 검증 결과를 유지했습니다.
- 발행 직전 코드 커밋 `2e308a3296c6431d3da06085d5098042c8de95f3`에서 대조 대상 14개 구현 파일의 SHA-256이 촬영·원고 작성 시점과 모두 같음을 확인했습니다.
- 303단계의 PDF·Markdown 문구 일치, 기존 292단계 ID·순서 유지, 83개 소섹션, 페이지 번호·버전·목차를 검사했습니다. 내부 링크 204개, 북마크 93개를 검증했습니다.
- 사용 이미지 156개의 해시와 교체 화면의 XML을 검증했습니다. 단계·캡처 대응과 폐기된 UI 안내의 잔존 여부를 점검했습니다.
- 검수 범위는 문서의 코드 일치·화면·조판·탐색입니다. 전체 서비스 종단간 테스트나 AI 정확성·실제 알림 전송 성공을 보증하지 않습니다.
- 발행 PDF SHA-256: `7da2ac0de2aef468aab9bfd625c78a2d7ef5bbf5493dc6ec4680de8f7f8af44d`

## 최종 교체 캡처 무결성

파일명은 로컬 검수 식별자이며 다운로드 링크가 아닙니다.

| 캡처 | 출처 | SHA-256 |
|---|---|---|
| `cabinet.png` | 이번 촬영 | `cc151819c9e1e654d810c8b9789b40cf6ab47ab356ec3d8aa620443003c510f9` |
| `caregiver-export.png` | 이번 촬영 | `a91b76f7cdc4c22034e9d75263660981be020a624d756644840b0c53e3ab59fe` |
| `caregiver-history.png` | 이번 촬영 | `b332121f3d3ede974d06cde3a537ab0389deba23133284aa22daf79d59d1b4f5` |
| `caregiver-home.png` | 이번 촬영 | `99806bf342e36f4e8d74a5ffde122b03a266c48de75306d2f185b4616e97876d` |
| `caregiver-prn-alert.png` | 이번 촬영 | `02d76ea739e73d54aa8aae360358cf2bed511cdd7d4c5103d92065a60c338ceb` |
| `caregiver-prn.png` | 이번 촬영 | `a150b9e1e41afb54bff95b04cd8a8a16740e2ccb74017d8a2f4544beadd0f225` |
| `caregiver-schedule.png` | 이번 촬영 | `52ef396b8e26cb36e0edb4f092930790a24b9801bf908d79a63d01178a934cf1` |
| `history-calendar.png` | 이번 촬영 | `1a88a54206fc608fc349980d1a8a43ce6bccb37420a44ef06aefe07c85338511` |
| `history-edit.png` | 이번 촬영 | `9ddd2a1b78223082811df17498af27f79c20cd48e56aaa05fe1ac512c0e93d72` |
| `history-export.png` | 이번 촬영 | `ac4fedbcf1f68fb8839b74c5275fe6786d3f3f42c3c0fbd37f28c65a3ca8a85f` |
| `history-info.png` | 이번 촬영 | `3e2529cd49a6a2651b00394988302ecf13f05179a2688ec3f45a38f62d8d55a6` |
| `history-prn.png` | 이번 촬영 | `db99dd72514a8f1e02bdc2406d56ec504d40c8227023e11eab25eb14b6d843c3` |
| `history-share-current.png` | 이번 촬영 | `c9514c2ce5e09b547f76ba1330078fae36a86c6ba372a776c79db979bd5e0d2b` |
| `management-menu.png` | 이번 촬영 | `a1e60ac72d2584203cb5a4f729b17ff3a3dd05241b343be8517c0609adc0fb6c` |
| `manual-lower.png` | 이번 촬영 | `297d628eec5b350838a5c3fd0fc9dbb0fa031c6f0176c2118f00d2654f34b7e5` |
| `manual-prn.png` | 이번 촬영 | `75b5d75482384a4ebfb4664497ba39de2d51c0ccea8bda55a986965d5860e3fb` |
| `manual-top.png` | 이번 촬영 | `0e1727eca2e79c822a66a5df033815e600d8f2d00aae9d4329c3e6672af737a7` |
| `patient-history.png` | 이번 촬영 | `d722069659400bec810eb0cd832080f31d64b98af2ac0b93c186f771ea76f5da` |
| `patient-home.png` | 이번 촬영 | `3136f1c13586a80f3cba18977a6cb6f03f1a356e1af430320a4119917e38678e` |
| `patient-schedule.png` | 이번 촬영 | `b939229bd2e0cf52214e0796f1632ab856fa3e167342ab41f0d5ccdcb4e603cf` |
| `prn-reminder.png` | 이번 촬영 | `6254385662d16c7b7c12293262c40d7a7db7f822e92713a2a74ded42b04ce6cd` |
| `prn-schedule.png` | 이번 촬영 | `5c6952c7a6a65aab91401a8e92a833754df8d4f6c5c8cc2590a044f7d0f0855a` |
| `prn_consistency_confirm.png` | 제공 자료 재사용 | `b2e7d3dbaa38ce38bd7478f905f385976db394a3004679befe9a12a7a8397937` |
| `regimen-edit.png` | 이번 촬영 | `975877cec6fed1dc869a75c464ec0ce5f12cafa7d00541f82ff2c4f60c6092fc` |
| `regimen-replace-confirm.png` | 이번 촬영 | `d2f5db4a16dcfe0c966132c93c420e892f7f279fb67fed197349837c9d0372fd` |
| `regimen-replace.png` | 이번 촬영 | `35c5ee35a3d5d4aec180aed95172fd2cd35e3dc4ab18dfd9a045e98eef458a21` |
| `regimen-stop-confirm.png` | 이번 촬영 | `2bf7c8edd236cd091b0f806bd94e93fae5a27624f2dc847fc8bc851a9374ad4b` |
| `regimen-stop.png` | 이번 촬영 | `01db81b9d59b789d3c6dc51e96926d2203f197032568fb96e113e59eb550c1d0` |

## 2026-10-21 본문 수정 (`beta/v0.2.4`)

README 본문만 현재 앱에 맞췄으며 PDF와 사진은 아직 다시 만들지 않았습니다. PDF를 다시
만들 때 아래 항목과 10월 19일 이후 바뀐 홈 화면(바로가기 아래 ‘연동된 환자 일정 보기’)
사진을 함께 반영해야 합니다.

- 상태 배지: ‘처방 교체’ → ‘처방 변경’, ‘중단·교체 예정’ → ‘복용 중단 예정·처방 변경 예정’(7.3, 7.10).
- 약 삭제 확인: 복용 기록도 함께 삭제된다는 안내와 ‘처방에 따른 복용 중단’ 안내, 취소가 왼쪽(7.6, 7.12).
- ‘연결된 환자’ → ‘연동된 환자’, ‘환자 연결’ → ‘환자 연동’(5.x 위젯, 9.5, 9.14).
- 홈의 ‘연동된 환자 일정 보기’ 안내(1.6), 일정 화면의 시간대 전체 취소 확인(3.4), 홈 기록 뒤 주의 문구의 30분 기준(3.2).
- 필요시 복용: 저장 알림의 실행 취소와 기록 수정의 ‘기록 취소(잘못 기록함)’, 복용 순서 표시(3.9).
- 복약 기록이 이번 달 달력으로 열리고 날짜를 눌러 하루 기록으로 들어가는 흐름(3.7). 달력 화면 사진이 새로 필요합니다.
