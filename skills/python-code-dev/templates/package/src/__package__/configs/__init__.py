"""Configuration package."""

from __PACKAGE__.configs.env import get_env, require_env
from __PACKAGE__.configs.paths import logs_root, output_root, repo_root

__all__ = ["get_env", "require_env", "logs_root", "output_root", "repo_root"]
