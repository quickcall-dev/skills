from pathlib import Path

from __PACKAGE__.configs.paths import logs_root, output_root, repo_root


def test_repo_root_resolves_project_root() -> None:
    assert (repo_root() / "pyproject.toml").exists()


def test_roots_are_absolute_paths() -> None:
    assert isinstance(output_root(), Path)
    assert output_root().is_absolute()
    assert logs_root().is_absolute()
