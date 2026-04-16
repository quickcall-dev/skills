"""Count vowels in a string. Optimize this."""

def count_vowels(text):
    count = 0
    for char in text:
        if char in "aeiouAEIOU":
            count += 1
    return count
