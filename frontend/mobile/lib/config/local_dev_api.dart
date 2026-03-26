/// Optional: point a **physical phone** at your PC’s local API.
///
/// Default app behavior uses the **hosted** API (Render). To run against a laptop
/// backend from a real device on the same Wi‑Fi:
///
/// 1. Find your PC IPv4 in PowerShell: `(Get-NetIPAddress -AddressFamily IPv4).IPAddress`
/// 2. Set [localDevPcHost] to that address, e.g. `'192.168.1.42'`.
/// 3. Run the backend: `uvicorn main:app --reload --host 0.0.0.0 --port 8100`
/// 4. Run the app — it will use `http://<localDevPcHost>:8100`.
///
/// **Android emulator / iOS simulator / local web:** leave [localDevPcHost] as `null`
/// and use `--dart-define=API_BASE=http://10.0.2.2:8100` (emulator) or
/// `http://127.0.0.1:8100` / `http://localhost:8100` as needed.
library;

/// Your PC’s LAN IP, or `null` to use the default hosted API.
const String? localDevPcHost = null;

/// Must match `uvicorn ... --port` (default 8100 in this project).
const int localDevApiPort = 8100;
