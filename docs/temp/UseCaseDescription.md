### Use Case Description: UC-1 처방전 이미지 입력

| Actor Action | System Response |
| --- | --- |
|  | 1. 처방전 촬영 또는 이미지 선택 화면을 출력한다. |
| 2. 처방전 촬영 또는 이미지를 선택한다. |  |
|  | 3. 선택된 이미지에서 개인정보가 보호된 결과 화면을 출력한다. |

---

### Use Case Description: UC-2 분석 결과 확인

| Actor Action | System Response |
| --- | --- |
|  | 1. 처방전 분석 결과로 확인된 약 이름, 용량, 복용 방법 등의 상세 정보를 화면에 출력한다. |

---

### Use Case Description: UC-3p 오늘의 복약일정 확인 (환자용)

| Actor Action | System Response |
| --- | --- |
|  | 1. 당일 복약해야 할 약 목록을 시간대별로 화면에 출력한다. |

Extensions   
Step 1 이후, 복약 완료 버튼을 선택하여 완료 상태를 화면에 반영한다. (UC-8)   
Step 1 이후, 알림 아이콘을 선택하여 알림 설정 팝업에서 설정한다. (UC-12)

---

### Use Case Description: UC-3u 오늘의 복약일정 확인 (사용자용)

| Actor Action | System Response |
|  --- | --- |
|  | 1. 당일 복약 일정 목록을 화면에 출력한다. |

Extensions   
Step 1 이후, 특정 약을 선택하여 상세 정보를 화면에 출력한다. (UC-9)   
Step 1 이후, 특정 약의 상세 정보를 확인하고 필요 시 음성 안내를 요청할 수 있다. (UC-9, UC-11)   
Step 1 이후, 건강관리 추천 버튼을 선택하여 건강 가이드를 확인할 수 있다. (UC-10)

---

### Use Case Description: UC-4p 저장된 복약정보 조회 (환자용)

| Actor Action | System Response |
| --- | --- |
|  | 1. 저장된 복약 정보 목록을 화면에 출력한다. |

Extensions   
Step 1 이후, 목록에서 특정 항목을 선택하여 정보를 수정하거나 삭제한다. (UC-5)

---

### Use Case Description: UC-4c 저장된 복약정보 조회 (보호자용)

|  Actor Action | System Response |
| --- | --- |
|  | 1. 연동된 환자의 복약 정보 목록을 화면에 출력한다. |

Extensions   
Step 1 이후, 알림 아이콘을 선택하여 복약 완료 알림 수신 여부를 설정한다. (UC-13)

---

### Use case description: UC-6 환자/보호자 연동

| Actor Action | System Response |
| --- | --- |
|  | 1. 연동 설정 화면을 출력한다. |
| 2. 환자는 코드 생성, 보호자는 코드 입력 버튼을 선택한다. |  |
|  | 3. 환자용 고유 코드 또는 코드 입력창을 화면에 출력한다. |
| 4. 보호자가 전달받은 코드를 입력하고 완료 버튼을 누른다. |  |
|  | 5. 연동 성공 여부와 관련된 메시지를 화면에 출력한다. |

Extensions   
Step 5 이후, 연동된 상태에서 연동 해제 버튼을 선택하여 연동을 종료한다. (UC-7)

---

### Use case description: UC-14 사용자 설정

| Actor Action | System Response |
| --- | --- |
|  | 1. 사용자 설정 화면을 출력한다. |
| 2. 글씨 크기, 읽기 속도, 언어 옵션을 선택 후 저장 버튼을 누른다. |  |
|  | 3. 변경된 설정을 시스템에 적용하고 메인 화면으로 전환한다. |
