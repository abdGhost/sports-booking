/// Local API target for **physical phones** (same Wi‑Fi as your PC).
///
/// 1. Find your PC IPv4 in PowerShell: `(Get-NetIPAddress -AddressFamily IPv4).IPAddress`
/// 2. Set [localDevPcHost] to that address, e.g. `'192.168.1.42'`.
/// 3. Run the backend: `uvicorn main:app --reload --host 0.0.0.0 --port 8100`
/// 4. Run the app: `flutter run` (no `--dart-define` needed).
///
/// Leave [localDevPcHost] as `null` to use defaults (**Android emulator** → `10.0.2.2`,
/// **iOS simulator / desktop** → `127.0.0.1`). `--dart-define=API_BASE=...` still overrides
/// everything if you need it in CI.
library;

/// Your PC’s LAN IP, or `null` for emulator/simulator defaults.
const String? localDevPcHost = null;

/// Must match `uvicorn ... --port` (default 8100 in this project).
const int localDevApiPort = 8100;
