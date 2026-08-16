import json

from __PACKAGE__.utils.atomic import atomic_write_json, atomic_write_text


def test_atomic_write_text(tmp_path) -> None:
    path = atomic_write_text(tmp_path / "out.txt", "hello")
    assert path.exists()
    assert path.read_text(encoding="utf-8") == "hello"


def test_atomic_write_json(tmp_path) -> None:
    path = atomic_write_json(tmp_path / "out.json", {"ok": True})
    assert json.loads(path.read_text(encoding="utf-8")) == {"ok": True}
