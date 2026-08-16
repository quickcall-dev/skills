import logging

from __PACKAGE__.utils import get_logger, setup_run_logger


def test_get_logger_returns_named_logger() -> None:
    logger = get_logger("test.logger")
    assert isinstance(logger, logging.Logger)
    assert logger.name == "test.logger"


def test_setup_run_logger_writes_file(tmp_path) -> None:
    log_path = tmp_path / "run.log"
    logger = setup_run_logger(f"test.logger.{id(log_path)}", log_path)
    logger.info("hello")
    assert "hello" in log_path.read_text(encoding="utf-8")
