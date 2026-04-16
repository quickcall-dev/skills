"""Count vowels in a string. Optimize this."""

VOWELS = set("aeiouAEIOU")

def count_vowels(text):
    return sum(1 for char in text if char in VOWELS)
