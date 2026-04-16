"""Count vowels in a string. Optimize this."""

def count_vowels(text):
    text_lower = text.lower()
    return sum(text_lower.count(v) for v in "aeiou")
