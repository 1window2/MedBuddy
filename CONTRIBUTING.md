# Contributing to MedBuddy

Thank you for your interest in contributing to the MedBuddy project! 
We welcome all contributions and believe that your participation will make this project even better. 
To ensure smooth collaboration, please make sure to read and follow the contribution guidelines below.

## 📌 Table of Contents
1. [How to Contribute](#1-how-to-contribute)
2. [Coding Conventions](#2-coding-conventions)
3. [Documentation Standards](#3-documentation-standards)
4. [Commit Message Guidelines](#4-commit-message-guidelines)

---

## 1. How to Contribute

1. `Fork` this repository.
2. Create a new branch. (`git checkout -b feature/amazing-feature`)
3. Commit your changes. (`git commit -m 'feat: Add amazing feature'`)
4. Push to the branch. (`git push origin feature/amazing-feature`)
5. Open a `Pull Request`. Please fill out the PR template checklist carefully.

---

## 2. Coding Conventions

Since MedBuddy is a full-stack project, we follow different naming conventions depending on the language.

### 🐍 Backend (Python / FastAPI)
* **File Names:** `snake_case` (e.g., `db_models.py`, `medication.py`)
* **Class Names:** `PascalCase` (e.g., `OCRService`, `DrugModel`)
* **Function & Variable Names:** `snake_case` (e.g., `process_text`, `search_keyword`)
* **Constants:** `UPPER_SNAKE_CASE` (e.g., `GEMINI_API_KEY`)
* **Type Hinting:** Type hinting is strictly required for all function parameters and return values.

### 🦋 Frontend (Dart / Flutter)
* **File Names:** `snake_case` (e.g., `drug_info.dart`, `api_service.dart`)
* **Class Names:** `PascalCase` (e.g., `MedicationViewModel`, `DrugInfo`)
* **Function & Variable Names:** `camelCase` (e.g., `identifyMedication`, `saveDrugToPillbox`)
* **Private Members:** Start with an underscore (`_`) if used only within a file or class. (e.g., `_isLoading`, `_setLoading()`)

---

## 3. Documentation Standards

This is the most important rule of our project. All major functions and methods must have a block comment at the top following the specified format. 
We support both Korean and English documentation for our global collaborators. Please use the language you are most comfortable with.

### 📝 English Comment Template

#### File Name
```python
# File Name: [File Name]
# Role: [Role Description]
```

#### Class
```python
# Class Name: [Class Name]
# Role: [Role description]
# Responsibilities:
#   - Responsibility 1: [Description]
#   ...
# Attributes:
#   - attribute_name : [Attribute description and type]
# Note (Optional): [Remarks]
class [ClassName]:
```

#### Function/Method
```python
# Function Name: [Function Name]
# Description:
# - [Detailed description]
# Parameters:
# - [parameter_name]: [Parameter description and type]
# ...
# Returns:
# - [Description of return value based on condition]
# ...
```

#### Complex Process (logic with 3+ steps)
```python
# [Step 1]: [One-line explanation of this step]
# [Step 2]: [One-line explanation of next step]
# ...
```

#### Inline Comment
```python
[complex code]  # [Explanation of its role and the intent behind it]
```

### 📝 Korean Comment Template

#### 파일명
```python
# 파일명: [파일명]
# 역할: [역할]
```

#### 클래스
```python
# 클래스명: [클래스명]
# 역할: [역할]
# 주요 책임:
#   - 책임 1: [설명]
#   ...
# 속성 :
#   - 속성이름 : [속성 설명 및 타입]
# 비고(선택): [비고]
class [클래스이름]:
```

#### 함수/메서드
```python
# 함수이름: [함수명]
# 함수역할:
# - [역할 상세 설명]
# 매개변수:
# - [변수명]: [변수 설명 및 타입]
# ...
# 반환값:
# - [반환 조건에 따른 반환값 설명]
# ...
```

#### 복잡한 프로세스 (3단계 이상의 경우)
```python
# [1단계]: [이 단계에 대한 간단한 한 줄 설명]
# [2단계]: [다음 단계에 대한 간단한 한 줄 설명]
# ...
```

#### 인라인 주석
```python
[복잡한 코드]  # [이 코드의 역할/의도 설명]
```

### 💡 적용 예시 / Applied Examples
**[Python - Korean]**
```python
# 함수이름: normalize_date
# 함수역할:
# - 문자열 안에서 날짜를 찾아 YYYY-MM-DD 형식으로 통일한다.
# - OCR 텍스트 전처리 과정에서 호출된다.
# 매개변수:
# - text: 날짜가 포함될 수 있는 원본 문자열
# 반환값:
# - 날짜 패턴을 찾으면 YYYY-MM-DD 형식의 문자열 반환
# - 찾지 못하면 None 반환
def normalize_date(text: str) -> Optional[str]:
    # 구현 내용...
```
**[Dart - English]**
```dart
// Function Name: normalizeDate
// Description:
// - Extracts a date from a string and standardizes it to YYYY-MM-DD format.
// - Called during the OCR text preprocessing stage.
// Parameters:
// - text: The original string that may contain a date.
// Returns:
// - Returns a YYYY-MM-DD formatted string if a date pattern is found.
// - Returns null if no date is found.
String? normalizeDate(String text) {
  // Implementation...
}
```
---

## 4. Commit Message Guidelines

We follow the Conventional Commits specification to maintain a consistent commit history.

#### `feat:` (New Feature)
Used when adding a new feature or a new functional capability to the application or server.
* **Example:** `feat: allow users to manually edit extracted drug names`
* **Example:** `feat: integrate secondary public DB for drug search`

#### `fix:` (Bug Fix)
Used when fixing a bug or restoring broken functionality.
* **Example:** `fix: correct AI prompt to auto-fix OCR typos`
* **Example:** `fix: increase API timeout to 60 seconds to prevent empty responses`

#### `docs:` (Documentation)
Used for documentation-only changes. No production code logic is modified.
* **Example:** `docs: add MIT license`
* **Example:** `docs: update README with CI status badges`

#### `chore:` (Chores & Configuration)
Used for changes to the build process, development environment, configuration files, or auxiliary tools/libraries.
* **Example:** `chore: add issue templates for bug reports and feature requests`
* **Example:** `chore: upgrade flutter dependencies to latest versions`
* **Example:** `chore: update setup-java action to v4 in frontend-ci`

#### `refactor:` (Code Refactoring)
Used for a code change that neither fixes a bug nor adds a feature, but improves the internal structure, readability, or performance of the code.
* **Example:** `refactor: optimize Gemini API call to summarize only the top result`

#### `style:` (Code Style & Formatting)
Used for changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc.).
* **Example:** `style: fix dart formatting issues`

#### `test:` (Testing)
Used when adding missing tests or correcting existing tests.
* **Example:** `test: add dummy test for CI pipeline`

