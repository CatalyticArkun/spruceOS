# Logger and Handler Typing

Category
- Typing fixes for logger setup and rotating handler stream usage.

Method
- Use precise handler/stream types.
- Avoid assigning None to non-optional fields without narrowing.

Examples
- `main-ui/utils/logger.py`: typed logger initialization.
- `main-ui/utils/etension_preserving_rotating_file_handler.py`: stream typing adjustments.
