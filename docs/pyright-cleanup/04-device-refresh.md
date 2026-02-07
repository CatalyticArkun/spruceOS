# Device Refresh and force_refresh Typing

Category
- Clarify optional refresh hooks on device status providers.

Method
- Treat `force_refresh` as optional and guard before calling.
- Use TypeGuard helpers to narrow callable objects.

Examples
- `main-ui/devices/miyoo_trim_common.py`: WiFi status refresh guarded.
- `main-ui/devices/gkd/gkd_device.py`: safe refresh of WiFi/IP getters.
