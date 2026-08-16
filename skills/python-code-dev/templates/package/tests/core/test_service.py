import pytest

from __PACKAGE__.core import ExampleService


def test_greet() -> None:
    assert ExampleService().greet("Kimi") == "Hello, Kimi!"


def test_greet_rejects_blank_name() -> None:
    with pytest.raises(ValueError, match="name must not be empty"):
        ExampleService().greet(" ")
