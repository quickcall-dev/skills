"""Count vowels in a string. Optimize this."""

VOWELS = set("aeiouAEIOU")

def count_vowels(text):
    count = 0
    for char in text:
        if char in VOWELS:
            count += 1
    return count
