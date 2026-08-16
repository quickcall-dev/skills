from __PACKAGE__.runner.cli import main


def test_cli_runs_example_pipeline(tmp_path) -> None:
    rc = main(["--message", "hello", "--output-root", str(tmp_path)])

    assert rc == 0
    assert list(tmp_path.glob("example/*/run_001/result.json"))
