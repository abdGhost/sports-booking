import 'package:flutter/foundation.dart';

import 'local_dev_api.dart';

/// Base URL for the FastAPI server.
///
/// **Default:** production API on Render ([_defaultProdBase]) for every platform
/// and mode — no `--dart-define` needed for normal run/release builds.
///
/// **Local backend:** use one of:
/// - `--dart-define=API_BASE=http://10.0.2.2:8100` (Android emulator)
/// - `--dart-define=API_BASE=http://127.0.0.1:8100` (iOS simulator / desktop / web)
/// - `--dart-define=API_HOST=192.168.x.x` with optional `API_PORT`
/// - Set [localDevPcHost] in `lib/config/local_dev_api.dart` for a **physical phone**
///   on the same Wi‑Fi (points at your PC).
///
/// **Flutter Web:** `10.0.2.2` in `API_BASE` is rewritten for the browser; production
/// HTTPS URL is unchanged.
class ApiConfig {
  ApiConfig._();

  static const String _fromEnv = String.fromEnvironment('API_BASE');
  static const String _defaultProdBase =
      'https://sports-booking-32gk.onrender.com';
  /// PC LAN IP or hostname, without scheme (e.g. `192.168.1.10`). Used on mobile when set.
  static const String _hostFromEnv = String.fromEnvironment('API_HOST');
  static const String _portFromEnv = String.fromEnvironment('API_PORT');

  /// Default host port — keep in sync with `uvicorn ... --port`.
  static const int _defaultPort = 8100;

  static int get _effectivePort {
    if (_portFromEnv.isNotEmpty) {
      return int.tryParse(_portFromEnv) ?? _defaultPort;
    }
    return localDevApiPort;
  }

  static String _sanitizeForWeb(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.host == '10.0.2.2') {
        return uri.replace(host: '127.0.0.1').toString();
      }
      // Match the dev server host (usually localhost) so CORS + PNA work in the browser.
      if (uri.host == '127.0.0.1') {
        return uri.replace(host: 'localhost').toString();
      }
      return raw;
    } catch (_) {
      return raw
          .replaceFirst('10.0.2.2', '127.0.0.1')
          .replaceFirst('127.0.0.1', 'localhost');
    }
  }

  static String get baseUrl {
    if (_fromEnv.isNotEmpty) {
      if (kIsWeb) {
        return _sanitizeForWeb(_fromEnv);
      }
      return _fromEnv;
    }
    if (_hostFromEnv.isNotEmpty) {
      final host = _hostFromEnv.trim();
      return 'http://$host:$_effectivePort';
    }
    if (!kIsWeb) {
      final local = localDevPcHost?.trim();
      if (local != null && local.isNotEmpty) {
        return 'http://$local:$_effectivePort';
      }
    }
    final prod = _defaultProdBase;
    if (kIsWeb) {
      return _sanitizeForWeb(prod);
    }
    return prod;
  }
}
