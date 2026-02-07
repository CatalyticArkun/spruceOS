# Type Guard Call-Site Usage (Games/Menus)

Category
- Use `has_*` TypeGuard helpers to safely call optional config methods in game/menu flows.

Method
- Import the relevant guard(s).
- Branch on the guard before calling the optional method.
- Provide defaults when the optional API is missing.

Examples
- `main-ui/games/utils/game_system.py`: guard `get_sort_order`, `get_brand`, `get_type`, `get_release_year`.
- `main-ui/menus/games/game_config_menu.py`: guard menu overrides and reload hooks.
