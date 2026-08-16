"""Core domain services."""


class ExampleService:
    """Provide a small class that is safe to extend.

    Methods:
        greet: Return a greeting for a required name.
    """

    def greet(self, name: str) -> str:
        """Return a greeting for a required name.

        Args:
            name: Required. Non-empty name to greet.

        Returns:
            Greeting string formatted as ``Hello, <name>!``.

        Raises:
            ValueError: If ``name`` is empty or whitespace only.
        """
        if not name.strip():
            raise ValueError("name must not be empty")
        return f"Hello, {name}!"
