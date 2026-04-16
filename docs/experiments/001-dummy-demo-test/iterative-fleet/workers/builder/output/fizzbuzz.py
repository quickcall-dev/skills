def fizzbuzz(n):
    if n <= 0:
        return []

    result = []
    for i in range(1, n + 1):
        if i % 15 == 0:
            result.append("FizzBuzz")
        elif i % 3 == 0:
            result.append("Fizz")
        elif i % 5 == 0:
            result.append("Buzz")
        else:
            result.append(str(i))

    return result


if __name__ == "__main__":
    for item in fizzbuzz(20):
        print(item)
