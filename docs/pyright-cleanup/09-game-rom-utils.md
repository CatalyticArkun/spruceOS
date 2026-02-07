# Game/Rom Utilities Typing

Category
- Typing cleanups in game/rom utility modules and game system helpers.

Method
- Tighten function signatures and container element types.
- Narrow optional values before use.
- Replace loose casts with explicit checks.

Examples
- `main-ui/games/game_system_utils.py`: helper return types.
- `main-ui/menus/games/utils/rom_select_options_builder.py`: optional handling for ROM metadata.
