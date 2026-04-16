def reverse(s):
    """Returns the reversed string."""
    return s[::-1]


def capitalize_words(s):
    """Capitalizes each word."""
    return ' '.join(word.capitalize() for word in s.split())
