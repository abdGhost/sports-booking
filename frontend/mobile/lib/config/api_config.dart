import 'package:flutter/foundation.dart';

import 'local_dev_api.dart';

/// Base URL for the FastAPI server.
///
/// **Physical device:** set [localDevPcHost] in `lib/config/local_dev_api.dart`, then
/// run `flutter run` with no flags.
///
/// **Android emulator:** leave `localDevPcHost` null — uses `10.0.2.2` (API must
/// listen on `0.0.0.0`).
///
/// **Overrides:** `--dart-define=API_BASE=...`, then `API_HOST` / `API_PORT`.
///
/// **Flutter Web:** uses `127.0.0.1`; `10.0.2.2` in `API_BASE` is rewritten for web.
class ApiConfig {
  ApiConfig._();

  static const String _fromEnv = String.fromEnvironment('API_BASE');
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
    // Flutter web is usually served at http://localhost:<port>. Use the same host
    // for the API so the browser does not treat 127.0.0.1 as a different origin
    // (PUT + Authorization preflight can otherwise fail silently).
    if (kIsWeb) {
      return 'http://localhost:$_effectivePort';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:$_effectivePort';
      default:
        return 'http://127.0.0.1:$_effectivePort';
    }
  }
}
