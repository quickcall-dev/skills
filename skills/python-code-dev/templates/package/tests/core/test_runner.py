from __PACKAGE__.core import ExampleRunner


def test_example_runner_writes_artifacts(tmp_path) -> None:
    result = ExampleRunner(output_root=tmp_path).run({"message": "hello"})

    assert result.status == "finished"
    assert result.metrics["message"] == "hello"
    assert (result.run_dir / "config.json").exists()
    assert (result.run_dir / "result.json").exists()
    assert (result.run_dir / "run.log").exists()
    assert (result.run_dir / "message.txt").read_text(encoding="utf-8") == "hello\n"
