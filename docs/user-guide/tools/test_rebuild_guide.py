# 파일명: test_rebuild_guide.py
# 역할: 설명서 재분류 후 절·단계·참고를 손실 없이 읽는지 검사한다.
"""Regression tests for reorganizing the guide's Markdown source."""
import unittest

from rebuild_guide import parse_markdown


# 클래스명: GuideMarkdownTests
# 역할: 장·절 재배치 후 설명서 원문을 읽는 규칙을 검증한다.
# 주요 책임: 절 수 변경, 참고 연결, 잘못된 구조의 거부를 검사한다.
# 속성: 별도 상태 없이 각 테스트의 원문을 사용한다.
class GuideMarkdownTests(unittest.TestCase):
    """고정된 절 수 대신 실제 구조의 무결성을 확인한다."""

    # 함수이름: test_variable_subsection_count
    # 함수역할: 고정된 절 수에 의존하지 않고 단계 본문을 보존하는지 검사한다.
    # 매개변수: self(GuideMarkdownTests)는 현재 테스트 인스턴스다.
    # 반환값: None. 절 순서나 본문이 다르면 테스트가 실패한다.
    def test_variable_subsection_count(self) -> None:
        """절을 추가·분리해도 단계와 원문이 유지된다."""
        source = '\n'.join(
            f'## {n} Chapter\n### {n}.1 Section\n#### 1. Step\nBody {n}'
            for n in range(1, 4)
        )
        groups = parse_markdown(source)
        self.assertEqual(list(groups), ['1.1', '2.1', '3.1'])
        self.assertEqual(groups['3.1']['steps'][0]['text'], 'Body 3')

    # 함수이름: test_relocated_notes_and_callouts
    # 함수역할: 이동한 절의 참고와 강조 설명이 해당 단계에 연결되는지 검사한다.
    # 매개변수: self(GuideMarkdownTests)는 현재 테스트 인스턴스다.
    # 반환값: None. 참고나 강조 설명이 달라지면 테스트가 실패한다.
    def test_relocated_notes_and_callouts(self) -> None:
        """새 절 번호의 참고와 사진 강조 설명을 올바른 단계에 연결한다."""
        source = (
            '## 7 Notifications\n### 7.9 Actions\n'
            '#### 1. Open\nOpen the notification.\n1. Body\n'
            '#### 2. Record\nConfirm the dose.\n'
            '### 참고\n**[7.9 - 15페이지 - 1, 2번 사진](guide.pdf#page=15)**\n'
            'Check the date first.\n'
        )
        steps = parse_markdown(source)['7.9']['steps']
        self.assertEqual(steps[0]['callouts'], [{'box_index': 0, 'text': 'Body'}])
        self.assertTrue(all(s['source_note'] == 'Check the date first.' for s in steps))

    # 함수이름: test_invalid_structure_is_rejected
    # 함수역할: 누락·중복된 절이나 단계 번호를 정상 원문으로 처리하지 않는지 검사한다.
    # 매개변수: self(GuideMarkdownTests)는 현재 테스트 인스턴스다.
    # 반환값: None. 잘못된 구조에서 검증 오류가 발생하지 않으면 테스트가 실패한다.
    def test_invalid_structure_is_rejected(self) -> None:
        """빈 원문·중복 절·잘못된 장 번호·누락된 단계 번호는 거부한다."""
        for source in [
            '',
            '## 1 Chapter\n### 1.1 A\n#### 1. Step\n### 1.1 B\n#### 1. Step',
            '## 1 Chapter\n### 2.1 A\n#### 1. Step',
            '## 1 Chapter\n### 1.1 A',
            '## 1 Chapter\n### 1.1 A\n#### 2. Step',
            '## 1 Chapter\n### 1.1 A\n#### 1. Step\n#### 3. Step',
            '## 1 Chapter\n### 1.1 A\n#### 1. Step\n#### 1. Step',
        ]:
            with self.subTest(source=source), self.assertRaises(AssertionError):
                parse_markdown(source)


if __name__ == '__main__':
    unittest.main()
