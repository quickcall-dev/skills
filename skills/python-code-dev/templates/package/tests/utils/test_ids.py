from __PACKAGE__.utils.ids import new_run_dir, today_str


def test_today_str_has_iso_shape() -> None:
    assert len(today_str()) == 10


def test_new_run_dir_increments(tmp_path) -> None:
    first = new_run_dir(tmp_path)
    second = new_run_dir(tmp_path)
    assert first.name == "run_001"
    assert second.name == "run_002"
