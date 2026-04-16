"""Count vowels in a string. Optimize this."""

def count_vowels(text):
    text_lower = text.lower()
    return sum(map(text_lower.count, "aeiou"))
