"""Count vowels in a string. Optimize this."""

def count_vowels(text):
    return sum(text.count(v) for v in "aeiouAEIOU")
