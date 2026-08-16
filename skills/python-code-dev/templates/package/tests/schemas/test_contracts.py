from pathlib import Path

from __PACKAGE__.schemas import Greeting, RunResult


def test_greeting_contract() -> None:
    assert Greeting(text="Hello").text == "Hello"


def test_run_result_contract() -> None:
    result = RunResult(run_dir=Path("run_001"), status="finished", metrics={"x": 1})
    assert result.status == "finished"
    assert result.metrics["x"] == 1
