import 'package:flutter/foundation.dart';

/// Base URL for the FastAPI server.
///
/// **Important:** `10.0.2.2` only works on the **Android emulator** (maps to your PC).
/// **Flutter Web (Chrome)** runs on the PC, so it must use `127.0.0.1` or `localhost`.
/// If you pass `--dart-define=API_BASE=...` with `10.0.2.2` and run on **web**, login
/// will time out — use `127.0.0.1` for web, or omit `API_BASE` and let [baseUrl] pick.
///
/// Physical phone: use your PC LAN IP, e.g. `http://192.168.1.10:8000`.
class ApiConfig {
  ApiConfig._();

  static const String _fromEnv = String.fromEnvironment('API_BASE');

  /// Default host port (matches backend `uvicorn` command).
  static const int _defaultPort = 8000;

  static String _sanitizeForWeb(String raw) {
    try {
      final uri = Uri.parse(raw);
      // Android emulator alias is not reachable from browser runtime.
      if (uri.host == '10.0.2.2') {
        return uri.replace(host: '127.0.0.1').toString();
      }
      return raw;
    } catch (_) {
      // Fallback for non-URI values passed via dart-define.
      return raw.replaceFirst('10.0.2.2', '127.0.0.1');
    }
  }

  static String get baseUrl {
    if (_fromEnv.isNotEmpty) {
      // Help: same run config often passes 10.0.2.2 for Android; web cannot use it.
      if (kIsWeb) {
        return _sanitizeForWeb(_fromEnv);
      }
      return _fromEnv;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:$_defaultPort';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:$_defaultPort';
      default:
        return 'http://127.0.0.1:$_defaultPort';
    }
  }
}
