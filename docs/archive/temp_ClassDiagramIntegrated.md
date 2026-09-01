# MedBuddy Class Diagram

## 1. 판단 기준

- Class Diagram은 시스템의 정적 구조를 보여야 하므로, 단순한 파일 목록이 아니라 책임, 속성, 연산, 관계를 기준으로 클래스를 도출한다.
- 강의 자료 기준으로 Use Case만으로는 분석 클래스 도출이 부족하며, Sequence Diagram과 Communication Diagram의 메시지 송수신 객체를 Boundary, Control, Entity로 분류해야 한다.
- 현재 구현 클래스와 목표 설계 클래스를 무비판적으로 합치면 문서가 거짓말을 하게 된다. 따라서 아래 다이어그램은 아직 구현 근거가 부족한 클래스를 `planned` 스테레오타입으로 표시하고, 별도 표시가 없는 클래스는 현재 구현 또는 현재 시퀀스의 직접 근거가 있는 클래스로 본다.
- `간병인`은 제외하고, 사용자 Actor는 `Patient`와 `Guardian`만 둔다.
- Figma의 화면 흐름은 `촬영 -> 분석중 -> 분석 완료 -> 결과 확인 -> 저장/조회/연동/설정`으로 이어진다. 따라서 UI Boundary는 화면 단위로 분리한다.
- README의 초기 Class Diagram은 실제 코드 파일을 잘 나열하지만, 일정, 보호자 연동, 알림, 사용자 설정 같은 목표 기능의 도메인 클래스가 부족하다.
- 동료 Communication Diagram은 클래스 후보를 잘 드러내지만, `Caregiver` 명명은 현재 범위와 맞지 않으므로 모두 `Guardian`으로 정리한다.

## 2. 주요 클래스 도출 논거

| 클래스 | 분류 | 생성 논거 |
| --- | --- | --- |
| `PrescriptionInputUI`, `PrescriptionResultUI` | Boundary | Figma와 Sequence Diagram에서 촬영, 분석중, 분석완료, 결과 카드 화면이 분리되어 나타난다. |
| `SavedMedicationUI`, `TodayMedicationUI`, `LinkUI`, `UserSettingUI` | Boundary | 저장 목록, 오늘 일정, 환자/보호자 연동, 환경설정 화면이 독립 화면으로 존재한다. |
| `MedicationAPIBoundary` | Boundary | Flutter와 FastAPI 사이의 HTTP API 경계다. 실제 코드에서는 `ApiService`, `MedicationViewModel`, `api/router.py`가 나누어 담당한다. |
| `PrescriptionAnalysisControl` | Control | 이미지 입력, OCR, Gemini Vision, 개인정보 마스킹, 후보 약물 생성 순서를 조정한다. |
| `MedicationSaveControl` | Control | 후보 약물명을 공공 API/Redis/LLM으로 보강하고 저장 트랜잭션을 조정한다. |
| `SavedMedicationControl` | Control | 환자/보호자 권한에 따라 저장 복약 정보 조회, 상세 확인, 삭제, 보호자 알림 설정을 조정한다. |
| `TodayMedicationControl` | Control | 오늘 복약 일정, 완료 체크, 알림, 건강 추천, TTS를 하나의 일정 중심 흐름으로 조정한다. |
| `PatientGuardianLinkControl` | Control | 환자 코드 생성, 보호자 등록, 연동 해제를 조정한다. |
| `UserSettingControl` | Control | 글씨 크기, 읽기 속도, 언어 설정 변경을 조정한다. |
| `MedicationCandidate` | Entity | 처방전 이미지에서 추출된 약 후보는 공공 DB로 검증된 약 상세 정보가 아니므로 `MedicationInfo`와 분리해야 한다. |
| `MedicationInfo` | Entity | 공공 의약품 API와 LLM 요약을 통해 보강된 약 상세 정보다. 캐시 가능하며 사용자 소유 정보가 아니다. |
| `SavedMedicationInfo` | Entity | 사용자가 약통에 저장한 약 정보다. `MedicationInfo`의 스냅샷이지만 사용자 소유, 삭제, 알림, 일정과 연결된다. |
| `MedicationSchedule`, `MedicationScheduleItem` | Entity | 복약 일정은 여러 약과 시간대의 반복 구조를 가지므로 별도 엔티티와 항목 클래스로 분리한다. |
| `MedicationAlarm`, `MedicationCompletion` | Entity | 알림 설정과 복약 완료 기록은 상태 변경 이력이므로 일정 항목에서 분리한다. |
| `PatientGuardianLink`, `PatientLinkCode`, `GuardianAlertSetting` | Entity | 보호자 연동과 알림 설정은 저장 복약 정보 조회 권한과 알림 발송 조건을 결정한다. |
| `UserSetting` | Entity | Figma 환경설정 화면과 Communication Diagram UC-14에서 글씨 크기, 읽기 속도, 언어가 독립 상태로 존재한다. |

## 3. Class Diagram

[PlantUML](https://www.plantuml.com/plantuml/png/l5hTSnkt4N-_lm9r7tfA9LlvS69pCfxoWtJOw4CZokapT019ZEyEB82JmgJDtrxi7K02noN4D9s-c13msyNkOh6xsFFVjA7AD5MP_SciUSN9OzdmZHAroKg-DCH8eiHgRGWJYXT6o3hJdqMzeOfMf2YfraDZb7Xi39yNibw8NpYvpDQ2SL88LPGy2_0RMdocAxumsv8JO4VhLSdx3Ccl6I4Z2rqfsTHiB4kfll_-4SPKRJzy87-U3cVVpMQ0aefnXI2-6htxUZJ4-5WXZP8bW6QpsJVJRsCsCU3otVZo4kF2QoFCjiLyENitVHynYTRVZjz_Spb1UVnikAffjzExsULi77E94U--_MhwVepnOTJGHwgva-RhsTkOJupuvltRoxVVONms9Qrhpfnbtaz6CPiOC1nTNhxD_frbxap9gs5XfDBa3Pd8YegQVD9SwLVjOT97RHGjZ3jVM261ZG12o5yRE_q3rUi1MHWbwbKtgsJ91ot9lHrrSqneAylsXbOy05jXYDlXZXfXsIER58fJmwz4_Nai6S_F1Xxhfs967nkgcA0rmadnbT26AqUV5vBjfDcpzGo0lMVDwwRQQUJOtGqVvjERXtRyyTFmVZ8VtZYyizU_BYuyqsZEx-0dBou-x9X71pHozuECGJNkpgRJyvgA-jESH9VeryZOW5WKYlCwFuiM7YIpgvo9Wa9uM3HLPUbptVsUzGv6SLqeiG7alDuq9htfc6vCepYwxx2cvVONQ-pZgrhe6HMbvP1pfQIwvbfRKoHakkUwAJ6X4DPZMMrARdYegaU55XbJnNIkMix7C3VIp62_l88fKNFmxHYye4zyqHG5rphlQG1BRCyiBNuFFA-NCY-5xeasKSrgmWqLPSxi450z00VTnx9U2bNToKspwPs0zyjXoPLP66fuNspdEQZOvyH7cxxyBTMYM7FMbDRsRX3l_GEdfLdVyq9M5QzPopvNqPynmQUDdUNiJicL0WDltA0dCTpY4yK4w1rTyRoqWwi3-xgR316dZHpdXF-y4NRB8G1xV3W3-xUSUWB1HLzmOqIzEb6kWA8LJtVZ8-RWJu8_Uqnlx_t93U_cFhYWdjTiIabPUCzoKS5574INpr-ixX9sf891t5q6Rf8RcnOj9TZqjzYFV-jejFNm0E_zrz8Wlj-HhBZfhUdSx-4Ma8qOt85mAzs3CijZ96N9QGssYyBnkAipi6YC6SN3mmB5cRSjuGuYgx-Ej8sJF5e7uxiZw40LrPyNlDR2Y2VUEfkYpm-TeKDAcEee7XjHilZ4yeBMJ83dwEJ97dCZC7H2JSN_sN1jzlWkFWrh1eJxpSyyNCloYK_SwKUHDUq-lEI56S5Mr41uSInSc1oGc6hlSukMC7I0N2JyBX71NxO25iLz0NLEB0K_Y_2e6N1Td5ltTiWtNSJgDZXqT7_JuGIYqE-2JRvoans3Y9jidIIL7H2J827EwOfN9BXvS1AVNaAb7K7XilunouJsFIT6L7nHIXFlXgMdQAjOjeT56_FYsM59LVKWLwjOodZBm9n8FVexJEgpsSw8Ps4v7IQpG1Qik4OgPrZeUGTaHBo63ZqKMMvpv9mTpvA_G-U0Qg_s86GM-lpCieFNRxvqW-X6t7FAe5JTSCvo5VmHeQvelMhQci4DpWwonXHU8MW9tm_Jo9F5nVJuWLNj7FcsBhU7wufNyeb7oM6qlUSh_dD-5Y3HY3xsCHaH1j9oxmK7in8gz3kk7iJ14XNbTjOUJbriupKZ3IqdTAjFbWZY_w5K5_iKvb84Gkho16NCJnrc7w6drSPiyx00WFcbgDceVRdctW0MWcmIAP18feXbrr9lXA7beNKt0Pi9DRtLdGvZsTJM2qHjTff64Y8wuzO6Pq4458PNXyBnvTAIzK-sqVoQcxLayVGpLRNzmxteuZKj6rNqvgZus0ZMdpI65kjXjvGxIE9jTLoZWtmOM2-8Y7xx_uCPS9LTm6P3UxpW073BaCEBak1ENIHKQeUPHtBXEaS4i7adGb1Enayxds9eMJIb1Vh76Tmf9fl7yaN9vzR0IUa3N5-3C8_7Apx1Oe6hTy3wWNxcTH02S7aXboS5fG18spWjeEVHHLNurpbRJQqTsLx2O3Pup_i_SV5T8yIEKZeKEzJ9Yfn-1j4MAVT6Ig-ar2f2dYnvJ7QOL5UyvYfv4VkbKzgqZ9yecEionDkwXDKkiJXbfIl8b51GYPrihx3yYrU0JTzCxj5h6aZITdtHZcDfiJT8CXPqaF-1nFYTeY37RPjv4JX-sP0A5bSYtKBt5Uc0pDoecm_hq049IzHktLUXriXk57Qm0ylx7lRqPZA_-TYEh-OtFqudxV1--jCjZ4DQBuYZN5mFhwxQqVLqClzqtR4Otd-SXbIHY9xowlOVxU3czjuoQOUpuU8XelFYEveVRzkVwSrXTUq-k90tre1ImPnhR8cusBuTto-uUX853nfVt57lpyFEm7UFkxZieYTtlpPAGhyNuaVGaC4gt3bmlElWTZ4frKPnn_X8KsYqxLeuZ_3RkrQy4hNuIUYkxOVozoqAeve2slTisfeXwllzVN5xqmilDgEB0leKOA8xgGmjKVQQKrMiHrIB0kzgEEu1UCYUQ5rmbiJ7dTwhQtV0g0m-Vi-Ku3Khjssb5NGQuvgdRK1ORm_5cCYYgU2x4NC3h1aJx8Js3E0DUzmdREFWK0Sqnr4saPhFQmr75ZPPXmqJqlBcj8fvtqWZbaxOqpPnZ_vUrPEtPOalzS0w9Ow8kKJHFUvXEouu8bRYtkwanxHOSn9z9Frr_rRRUKm1i1_vziNEym75ENcYPGFD85CUhQ4c8rG4KMkkecOVqcO-sulRGuAaSMFfZpRuO9FJcsN0fJr4bxlSMOQwOMLaNko6o0UOo5I8fy6c_SyhWVG_qL8mVDs9TAolTFPVDP-kP45BfxzBAkcR0aAUsdi2NKDivETMYB-GNIQmduLTyojpNtjVl_vmhCiw82w8Q-A-RcR8frlWaFnOCR3KZvMmNDgudw6VMe49zX40oDt72_lBMfVCUaxho7kpUtghWzg-gMWDLjU0WWQjpcArNpI6za_XBelf38xR4I6Ei2S4ZzWH1GVbQ8EPOBDkmfF18SuK1FgQlNcqbOhz9P1ws-zigPF1Fz0Do0yF3tUaiiON6wfCub1Iz90oaTCuZGv5lEHD2Ih4VP9ut5_0qk7-X3e1ieHKm0yf1xF3AK0YTLeAtY-taeB0V_peDu5V93ZI6SqI3STNNxuYNrnSa5UNhrz_yGhZOCyQAXCghFVY6tHSvCjSIlYafa_J6nTtGBgULtkHka-6f9JoSxFPHnNKV-00WX8X0S9ArmHyNrlY8D2etqGT4FSzKoTea5vbe3ws2k8S4EYQRlHQ6YANMLIXzCuCtquRgUnkBYosD2-HoESkp2ryW7RBf0lSK1ttfG_j6SgOmc77XE1Jvap0qOv3vYTZEw3OxjOinQe1-w48Hmsx0Jzlum6fP2sCL3WPA8yLx61oNxoTaxOqEoVxqkkSn5siVjB4lTKpp0wdaCY1D6onu14Z-cR0dGggGqQisFq-QqITa491x6KwGnkTfpCff68wRRj8lXGK4oM1nxgT21w_IGWEYM0f5Bm_qwY4OthVXXZjUsrjEOL7beDswO3ubxF6AR323SBNcYgkoRCmQ-Jo9WYNiYpbiywGLJYBi569G89Jwwjo4ZnUJf60pU7lLAn4cGOvYD2YuDfvzHzW00SDDR2lUTiIsLaRVi82sUU9S0hKzwt4_aBSqEmlkfPWH1KQDPZ68A0Xyh3BibeQxlx7_7yAjQASX84W-iyfvWHo1HC_rJCO_D2GM346_2Qcyb5g9B4hbMn9YQX0QbAWO4dgXNPcx-0EBOGO4fD-RBipy-QzQRkpJMiNUrSGxTlKZq0j8Xu5_byZC0ijJaRuc5BGtFrFXbwRG456eG0jR7oMAZONkYri3mzAE4-qdrA_0pI8TSyjat3n8oiN3YgDqNbNAvS-cw2V8Yr6MlWO3d6S0Dr7r1klVLikoL0jNGeI1g6UnsOCmBiE9bTGFA_LwpMBEUxfVGkA64-fwvb4TsmuvxofXRohLVCitnoUtMoxOWfiO3PBgOLSeslFna6edRG8cFiMCSkd9t1ShOEQ_U10ekE1KSF80EXt-Cn0g6bSJ9k3fzKyB6cne7O41i3GfPT4VQVO7r5txOJs6sj5mg7_5DZt09htizMutfQqMhcyhLXSxQCAVyEwCxSvJXvezSL5tkWryqZQ1fzi2Pje93DEMRSMffGRERQf79fHmxhw1G00)

## 4. README 초기 Class Diagram과의 차이

- README의 기존 Class Diagram은 실제 파일 구조를 추적하는 데는 유용하지만, `MedicationSchedule`, `MedicationAlarm`, `MedicationCompletion`, `PatientGuardianLink`, `GuardianAlertSetting`, `UserSetting` 같은 목표 기능 클래스가 부족하다.
- 기존 README는 `MedicationRouter`, `OCRService`, `DrugService`, `SavedMedication`, `DrugInfo` 등 구현 클래스 중심이다. 새 다이어그램은 이를 `MedicationAPIBoundary`, `PrescriptionAnalysisControl`, `MedicationSaveControl`, `SavedMedicationInfo`, `MedicationInfo`로 재배치하여 BCE 책임을 더 명확히 했다.
- 기존 README는 `VisionService`와 `PrescriptionParser_Dart`를 포함하지만, 현재 주요 흐름은 `processMedicationImage()`가 이미지 파일을 서버에 보내고 백엔드 `OCRService`가 Gemini Vision을 호출한다. 따라서 핵심 설계에서는 프론트 ML Kit 경로를 제외했다.
- 기존 README는 보호자/연동/알림/일정 기능을 정적 구조로 설명하지 못한다. Figma와 Communication Diagram은 이 기능들을 명확히 요구하므로, 새 다이어그램에는 `planned` 클래스로 반영했다.

## 5. 구현 관점에서 바로 보이는 보완점

- `SavedMedication`에 사용자 소유권(`patientHash` 또는 user id)이 없다. 보호자 조회, 일정 생성, 알림 설정을 구현하려면 저장 약 정보가 누구의 것인지 알아야 한다.
- 현재 저장 약 정보에는 복용 시간, 복용 기간, 1일 횟수 같은 처방 후보 정보가 저장되지 않는다. `MedicationCandidate`와 `SavedMedicationInfo` 사이의 변환 정책이 필요하다.
- 일정/알림/완료 기능은 DB 모델이 아직 없다. `MedicationScheduleItem`, `MedicationAlarm`, `MedicationCompletion`에 해당하는 테이블 또는 문서 구조가 필요하다.
- 환자/보호자 연동을 구현하려면 `PatientGuardianLink`, `PatientLinkCode`, `GuardianAlertSetting` 저장소가 필요하다.
- `MedicationInfo`는 공공 DB/LLM 결과이고 `SavedMedicationInfo`는 사용자 저장 스냅샷이다. 둘을 같은 클래스로 뭉치면 캐시, 저장, 삭제, 사용자 권한 책임이 뒤섞인다.
