# 사용자 가이드 재생성

`README.md`가 본문 원본입니다. `source/layout.json`은 84개 소섹션과 310단계의
식별자·스크린샷·크롭·강조 좌표를 연결합니다. 기존 스크린샷 148개는 함께 배포하는
`MedBuddy_User_Guide_ko.pdf` 안에서 추출해 `source/pdf-images.json`의 픽셀 해시와
대조합니다. 별도의 대용량 원본 이미지 폴더나 중복 기준 PDF를 추가하지 않습니다.
`source/assets.sha256.json`은 기존 캡처 7개, 기능 찾기 위젯 캡처 4개와 최신 로고의 해시입니다.
모든 입력 경로는 `docs/user-guide` 기준 상대 경로입니다.
이전 작업 폴더, 앱 빌드, 서버, 에뮬레이터, 계정이나 비밀 설정은 필요하지 않습니다.
재생성은 저장소에 포함된 기존 PDF를 입력으로 사용하므로 먼저 삭제하지 마세요.
PDF의 설명·번호·강조 표시는 벡터로 다시 조판하며, 페이지 전체를 사진으로 바꾸지 않습니다.

## 준비

- Python 3.12와 `tools/requirements.txt`의 라이브러리.
- Poppler의 `pdftoppm` 실행 파일. PATH에 추가하거나 `--poppler`로 지정합니다.
- `NanumBarunGothic.ttf`, `NanumBarunGothicBold.ttf`가 있는 폴더.
  글꼴은 이 저장소에 포함하지 않습니다. 설치된 글꼴 폴더를 `--font-dir`로 전달합니다.
  검수에 사용한 글꼴 해시는 `source/build-verification.json`에 기록합니다.

가상환경을 사용하는 경우 저장소 밖에 만들고 아래 명령의 `python`을 그 실행 파일로
바꿔도 됩니다. 생성 파일은 이 가이드의 `.build` 안에만 만들어집니다.

## 빌드와 검수

저장소 루트에서 다음을 실행합니다. `$fontDir`은 실행 환경의 글꼴 폴더로 지정하세요.

```powershell
python -m pip install -r docs/user-guide/tools/requirements.txt
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Fonts'
python -B docs/user-guide/tools/rebuild_guide.py build --font-dir $fontDir
python -B docs/user-guide/tools/rebuild_guide.py render
```

운영체제에 관계없이 같은 글꼴 파일을 가진 폴더를 지정하면 됩니다.
빌드는 이미지 해시, 전체 단계의 PDF 본문 일치, 목차·내부 링크·북마크를 검사합니다.
본문이 길면 기존 4단계 레이아웃에서 2단계 넓은 레이아웃으로 전환하며 글을 줄이지 않습니다.
README 페이지 링크와 PDF 참고 링크는 같은 조판 결과에서 계산합니다.

후보 PDF·README·검수 JSON과 전체 페이지 렌더는 `.build`에서 확인합니다.
전체 검토 시트뿐 아니라 변경 페이지를 확대해 잘림·겹침·화면과 설명의 대응을 직접 확인해야
합니다. 자동 검사가 성공해도 시각 검수가 끝난 것으로 표시하지 않습니다.

검토 완료 후 `.build/audit.json`의 `visual_qa`를 `reviewed`로 바꾸고 발행합니다.
이 값은 새 빌드마다 `pending`으로 돌아갑니다.

```powershell
python -B docs/user-guide/tools/rebuild_guide.py publish
```

발행은 PDF와 README만 교체합니다. Git 작업이나 앱 코드 변경은 하지 않습니다.
검수 중 원본 README가 바뀌었다면 발행을 중단하므로 다시 빌드·검수하세요.
발행 검수 요약은 `source/build-verification.json`과 `SOURCE_NOTES.md`에 기록합니다.
이 검수 요약은 입력 파일이 아니며 이후 재생성 때 결과와 함께 갱신해야 합니다.

## 내용 수정

본문·참고·소섹션 제목은 README에서 수정합니다. 단계 추가·삭제 또는 새 캡처 적용은
`source/layout.json`의 같은 소섹션과 단계 번호도 함께 수정합니다. 새 이미지의 해시를
`source/assets.sha256.json`에 등록하고 실제 화면과 구현을 대조한 뒤 사용하세요.
이미지나 단계가 누락되면 빌드는 실패합니다. 검토되지 않은 캡처를 자동으로 찾거나
스크린샷을 합성하는 기능은 없습니다.

기능 찾기 4장은 제품 위젯을 독립 실행한 화면이며 실행 중인 기기 캡처가 아닙니다.
이 PNG들은 이미 검수된 입력이므로 PDF 재생성에 Flutter나 앱 실행은 필요하지 않습니다.
캡처 범위·테스트 글꼴·구버전 화면 표시는 `SOURCE_NOTES.md`와 본문 1.7을 참고하세요.
