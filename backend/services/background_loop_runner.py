# 파일명: background_loop_runner.py
# 역할: 서버 수명 동안 도는 반복 작업의 시작과 종료 대기를 한 곳에서 제공한다.

import asyncio


# 클래스명: BackgroundLoopRunner
# 역할:
# - 반복 작업을 한 번만 시작하고, 종료 신호를 보낸 뒤 진행 중인 주기가 끝날 때까지 기다린다.
# 주요 책임:
# - 하위 클래스는 _run_loop에서 _stop_event를 확인하며 자신의 주기를 구현한다.
# 속성:
# - _task / _stop_event: 반복 태스크와 종료 신호.
class BackgroundLoopRunner:
    # 함수이름: __init__
    # 함수역할:
    # - 반복 태스크 자리와 종료 신호를 초기화한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 반복 작업은 start에서 시작한다.
    def __init__(self) -> None:
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    # 함수이름: start
    # 함수역할:
    # - 아직 시작하지 않았으면 현재 이벤트 루프에 반복 태스크를 만든다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음.
    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    # 함수이름: stop
    # 함수역할:
    # - 종료 신호를 보내고 진행 중인 주기가 끝날 때까지 기다린다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 반복 태스크가 끝난 뒤 완료된다.
    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    # 함수이름: _run_loop
    # 함수역할:
    # - 하위 클래스가 종료 신호까지 반복할 작업을 구현한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음.
    async def _run_loop(self) -> None:
        raise NotImplementedError
