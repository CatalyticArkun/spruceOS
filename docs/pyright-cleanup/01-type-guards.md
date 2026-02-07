# Type Guards and Protocol Interfaces

Category
- New Protocol interfaces and TypeGuard helpers to make runtime checks visible to Pyright.

Method
- Define minimal Protocols that describe the callable surface used at runtime.
- Provide `has_*` helpers that return `TypeGuard[...]` so narrowing is automatic.

Examples
- `main-ui/utils/type_guards.py`: `HasMenuOverrides` + `has_menu_overrides`.
- `main-ui/utils/type_guards.py`: `HasForceRefresh` + `has_force_refresh`.
