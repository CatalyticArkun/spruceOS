# WiFi Scanner Safety Guards

Category
- Safer scanner creation and use in WiFi menus.

Method
- Guard scanner access with runtime checks (instance checks / None checks).
- Avoid assuming scanner availability when UI state or platform config doesn’t provide it.

Examples
- `main-ui/devices/gkd/connman_wifi_menu.py`: safe scanner access in menu setup.
- `main-ui/menus/settings/wifi_menu.py`: guard scanner creation/usage for device types.
