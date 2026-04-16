import sys

sys.path.insert(0, "/home/sagar/skills/docs/experiments/001-dummy-demo-test/workers/hello/output")
sys.path.insert(0, "/home/sagar/skills/docs/experiments/001-dummy-demo-test/workers/utils/output")

from hello import greet
from utils import reverse, capitalize_words


# greet() tests
def test_greet_name():
    assert greet("Alice") == "Hello, Alice!"


def test_greet_world():
    assert greet("World") == "Hello, World!"


def test_greet_empty():
    assert greet("") == "Hello, !"


# reverse() tests
def test_reverse_word():
    assert reverse("hello") == "olleh"


def test_reverse_sentence():
    assert reverse("abc def") == "fed cba"


def test_reverse_empty():
    assert reverse("") == ""


# capitalize_words() tests
def test_capitalize_words_basic():
    assert capitalize_words("hello world") == "Hello World"


def test_capitalize_words_already_caps():
    assert capitalize_words("HELLO WORLD") == "Hello World"


def test_capitalize_words_single():
    assert capitalize_words("python") == "Python"
