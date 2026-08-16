import os

from __PACKAGE__.configs.env import get_env, load_env, require_env


def test_load_env_reads_file_without_overriding_existing(tmp_path, monkeypatch) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text("EXAMPLE_VALUE=from-file\nEXISTING=from-file\n", encoding="utf-8")
    monkeypatch.setenv("EXISTING", "from-env")
    monkeypatch.delenv("EXAMPLE_VALUE", raising=False)

    load_env(env_file)

    assert os.environ["EXAMPLE_VALUE"] == "from-file"
    assert os.environ["EXISTING"] == "from-env"


def test_get_env_returns_default_for_missing_key(monkeypatch) -> None:
    monkeypatch.delenv("MISSING_VALUE", raising=False)
    assert get_env("MISSING_VALUE", "fallback") == "fallback"


def test_require_env_raises_for_missing_key(monkeypatch) -> None:
    monkeypatch.delenv("REQUIRED_VALUE", raising=False)
    try:
        require_env("REQUIRED_VALUE")
    except RuntimeError as exc:
        assert "REQUIRED_VALUE" in str(exc)
    else:
        raise AssertionError("require_env should raise RuntimeError")
