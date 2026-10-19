# 파일명: background_loop_runner.py
# 역할: 서버 수명 동안 도는 반복 작업의 시작과 종료 대기를 한 곳에서 제공한다.

import asyncio
import logging


# 클래스명: BackgroundLoopRunner
# 역할:
# - 반복 작업을 한 번만 시작하고, 종료 신호를 보낸 뒤 진행 중인 주기가 끝날 때까지 기다린다.
# 주요 책임:
# - 종료 신호까지 _run_once를 별도 스레드에서 실행하고, 실패한 주기는 오류 종류만 기록한 뒤
#   _cycle_interval_seconds만큼 또는 종료 신호까지 기다렸다가 다음 주기를 이어간다.
# - 하위 클래스는 _run_once, _cycle_interval_seconds, _cycle_logger, _cycle_failure_message를 제공한다.
# 속성:
# - _task / _stop_event: 반복 태스크와 종료 신호.
# - _cycle_logger (logging.Logger): 실패한 주기를 기록할 하위 클래스 모듈의 로거.
# - _cycle_failure_message (str): 오류 종류 이름 하나를 받는 %s가 들어간 주기 실패 로그 형식.
class BackgroundLoopRunner:
    _cycle_logger: logging.Logger
    _cycle_failure_message: str

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
    # - 동기 작업 한 주기를 별도 스레드에 맡긴 뒤 주기 간격 또는 종료 신호까지 대기한다.
    # - 세션 생성·롤백·종료까지 실패한 주기도 기록만 하고 같은 간격으로 다음 주기를 이어간다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 종료 이벤트가 설정되면 반복을 마친다.
    async def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                await asyncio.to_thread(self._run_once)
            except Exception as exc:
                self._cycle_logger.error(
                    self._cycle_failure_message,
                    type(exc).__name__,
                )
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self._cycle_interval_seconds(),
                )
            except TimeoutError:
                continue

    # 함수이름: _run_once
    # 함수역할:
    # - 하위 클래스가 한 주기에 실행할 동기 작업을 구현한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음.
    def _run_once(self) -> None:
        raise NotImplementedError

    # 함수이름: _cycle_interval_seconds
    # 함수역할:
    # - 하위 클래스가 다음 주기까지 기다릴 시간을 주기마다 다시 계산해 돌려준다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 다음 주기까지 기다릴 시간(초).
    def _cycle_interval_seconds(self) -> float:
        raise NotImplementedError
