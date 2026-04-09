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
* **Class Names:** `PascalCase` (e.g., `OCRService`, `DrugModel`)
* **Function & Variable Names:** `snake_case` (e.g., `process_text`, `search_keyword`)
* **Constants:** `UPPER_SNAKE_CASE` (e.g., `GEMINI_API_KEY`)
* **Type Hinting:** Type hinting is strictly required for all function parameters and return values.

### 🦋 Frontend (Dart / Flutter)
* **Class Names:** `PascalCase` (e.g., `MedicationViewModel`, `DrugInfo`)
* **Function & Variable Names:** `camelCase` (e.g., `identifyMedication`, `saveDrugToPillbox`)
* **Private Members:** Start with an underscore (`_`) if used only within a file or class. (e.g., `_isLoading`, `_setLoading()`)

---

## 3. Documentation Standards ⭐

This is the most important rule of our project. All major functions and methods must have a block comment at the top following the specified format. 
We support both Korean and English documentation for our global collaborators. Please use the language you are most comfortable with.

### 📝 함수 주석 템플릿 (Korean Template)
```python
# 함수이름: [함수명]
# 함수역할:
# - [역할 상세 설명 1]
# - [역할 상세 설명 2]
# 매개변수:
# - [변수명]: [변수 설명 및 타입]
# 반환값:
# - [반환 조건 1에 따른 반환값 설명]
# - [반환 조건 2에 따른 반환값 설명]
```

### 📝 Function Comment Template (English Template)
```python
# Function Name: [Function Name]
# Description:
# - [Detailed description 1]
# - [Detailed description 2]
# Parameters:
# - [parameter_name]: [Parameter description and type]
# Returns:
# - [Description of return value based on condition 1]
# - [Description of return value based on condition 2]
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

## 4. Commit Message Guidelines

We follow the Conventional Commits specification to maintain a consistent commit history.

- `feat:` A new feature
- `fix:` A bug fix
- `docs:` Documentation only changes (README, CONTRIBUTING, etc.)
- `style:` Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc.)
- `refactor:` A code change that neither fixes a bug nor adds a feature
- `test:` Adding missing tests or correcting existing tests
- `chore:` Changes to the build process or auxiliary tools and libraries

#### Exmaple
- `feat: Add OCR image parsing and JSON structuring features`

