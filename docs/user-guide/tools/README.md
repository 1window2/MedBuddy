# 사용자 가이드 재생성

`README.md`가 본문 원본입니다. `source/layout.json`은 84개 소섹션과 327단계의
식별자·스크린샷·크롭·강조 좌표를 연결합니다. 모든 스크린샷은 `assets/`와
`source/assets/`에 파일로 있고, `source/assets.sha256.json`이 그 파일과 표지 로고의
해시를 기록합니다. 빌드는 단계가 쓰는 사진마다 이 해시를 대조합니다.
모든 입력 경로는 `docs/user-guide` 기준 상대 경로입니다.
이전 작업 폴더, 앱 빌드, 서버, 에뮬레이터, 계정이나 비밀 설정은 필요하지 않습니다.
PDF의 설명·번호·강조 표시는 벡터로 다시 조판하며, 페이지 전체를 사진으로 바꾸지 않습니다.
기본 배포 파일 `MedBuddy_User_Guide_ko.pdf`는 가로본이며,
세로본은 `MedBuddy_User_Guide_ko_portrait.pdf`로 구분합니다.

## 준비

- Python 3.12와 `tools/requirements.txt`의 라이브러리.
- 전체 페이지 검수에는 포함된 `pypdfium2`를 사용합니다. 기존 Poppler 방식도 사용할 수 있습니다.
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
python -B docs/user-guide/tools/review_guides.py docs/user-guide/.build/MedBuddy_User_Guide_ko_portrait.pdf docs/user-guide/.build/review-portrait
```

macOS에서는 저장소 밖의 Python 3.12 가상환경을 쓰고 Homebrew Poppler를 지정하면 됩니다.

```sh
uv venv -p 3.12 "$VENV"
VIRTUAL_ENV="$VENV" uv pip install -r docs/user-guide/tools/requirements.txt
"$VENV/bin/python" -B docs/user-guide/tools/rebuild_guide.py build --font-dir "$FONT_DIR"
"$VENV/bin/python" -B docs/user-guide/tools/rebuild_guide.py render --poppler /opt/homebrew/bin/pdftoppm
```

운영체제에 관계없이 같은 글꼴 파일을 가진 폴더를 지정하면 됩니다.
빌드는 이미지 해시, 전체 단계의 PDF 본문 일치, 목차·내부 링크·북마크를 검사합니다.
세로본은 소섹션 제목을 본문 위에 표시하고, 사진 아래에 설명을 두어 한 쪽에 최대
4단계(2열×2행)를 배치합니다. 별도의 소섹션 표지 페이지는 만들지 않습니다.
사진·설명이 들어가지 않으면 2단계로 나누며, 글이나 사진을 잘라내지 않습니다.
한 행의 사진 너비와 설명 시작선을 맞추고 원본 사진 비율을 유지합니다.
README의 개별 단계 페이지 링크는 세로본 조판 결과에서 계산하며, `_portrait.pdf`로 연결합니다.
기본 가로본은 README 첫머리에서 열 수 있고, PDF 안의 목차·참고 링크는 각 판의 페이지를 따릅니다.

후보 PDF·README·검수 JSON과 전체 페이지 렌더는 `.build`에서 확인합니다.
전체 검토 시트뿐 아니라 변경 페이지를 확대해 잘림·겹침·화면과 설명의 대응을 직접 확인해야
합니다. 자동 검사가 성공해도 시각 검수가 끝난 것으로 표시하지 않습니다.

검토 완료 후 `.build/audit.json`의 `visual_qa`를 `reviewed`로 바꾸고 발행합니다.
이 값은 새 빌드마다 `pending`으로 돌아갑니다.

```powershell
python -B docs/user-guide/tools/rebuild_guide.py publish
```

이 발행 명령은 세로본 PDF와 README만 교체합니다. 기본 가로본을 덮어쓰지 않으며,
Git 작업이나 앱 코드 변경은 하지 않습니다.
검수 중 원본 README가 바뀌었다면 발행을 중단하므로 다시 빌드·검수하세요.
발행 검수 요약은 `source/build-verification.json`과 `SOURCE_NOTES.md`에 기록합니다.
이 검수 요약은 입력 파일이 아니며 이후 재생성 때 결과와 함께 갱신해야 합니다.

## 내용 수정

본문·참고·소섹션 제목은 README에서 수정합니다. 단계 추가·삭제 또는 새 캡처 적용은
`source/layout.json`의 같은 소섹션과 단계 번호도 함께 수정합니다. 새 이미지의 해시를
`source/assets.sha256.json`에 등록하고 실제 화면과 구현을 대조한 뒤 사용하세요.
이미지나 단계가 누락되면 빌드는 실패합니다. 검토되지 않은 캡처를 자동으로 찾거나
스크린샷을 합성하는 기능은 없습니다.

2026-11-07의 추가 캡처는 제품 위젯에 가상 자료를 넣어 독립 실행한 화면이며,
실행 중인 기기 캡처나 실제 저장·전송의 증거가 아닙니다.
이 PNG들은 이미 검수된 입력이므로 PDF 재생성에 Flutter나 앱 실행은 필요하지 않습니다.
캡처 범위·테스트 글꼴·구버전 화면 이력은 `SOURCE_NOTES.md`에서 관리합니다.
사용자 본문에는 조작에 필요한 안내만 남기고, 촬영·검수 과정은 반복해서 넣지 않습니다.

## 가로본

세로본을 빌드한 뒤 같은 원고로 가로본을 만듭니다. 한 줄에 네 단계를 배치하고,
설명이 길면 다음 칸에 이어 씁니다. 두 판 모두 전체 단계와 참고 문구를 검증합니다.
가로본도 제목만 있는 장 구분 페이지를 생략하고 목차·북마크를 본문 첫 쪽에 연결합니다.
단계 제목 아래에는 6pt, 사진 아래에는 8pt 간격을 둡니다. 사진은 비율을 유지하며
최대 366pt 높이까지 확대하되, 설명이 긴 단계는 같은 칸에 들어가도록 확대 폭을 줄입니다.
단계 번호·사진·설명의 왼쪽 시작선을 맞추고, 네 칸의 바깥 여백을 좌우 대칭으로 둡니다.
강조 번호는 사진 왼쪽의 칸 사이 여백에 배치하며 사진 안쪽으로 밀어 넣지 않습니다.
두 판의 표지에는 제목과 `ver 1.0.0`을 표시합니다.

```powershell
python -B docs/user-guide/tools/build_landscape.py --font-dir $fontDir
python -B docs/user-guide/tools/review_guides.py docs/user-guide/.build/MedBuddy_User_Guide_ko.pdf docs/user-guide/.build/review-landscape
```

가로본은 별도로 전체 화면을 검토한 뒤 발행 위치에 복사합니다. 두 판의 검수 기록은
`source/build-verification.json`에 함께 남깁니다.
