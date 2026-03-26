import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

void _log(String message) {
  debugPrint('[Geocode] $message');
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final String? value;
  final DateTime expiresAt;
}

String _cacheKey(double lat, double lng) {
  // Match backend `round(lat, 4)` so GPS jitter maps to one cache slot (~11 m).
  final rLat = (lat * 10000).round() / 10000;
  final rLng = (lng * 10000).round() / 10000;
  return '$rLat,$rLng';
}

final Map<String, _CacheEntry> _reverseCache = <String, _CacheEntry>{};
final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};

Future<String?> _reverseGeocodeWeb(double lat, double lng) async {
  try {
    final uri = Uri.parse('${ApiConfig.baseUrl}/geocode/reverse').replace(
      queryParameters: {'lat': lat.toString(), 'lon': lng.toString()},
    );
    final res = await http
        .get(uri)
        .timeout(const Duration(seconds: 15), onTimeout: () {
      throw Exception('Geocode request timed out — check API is running and reachable.');
    });
    if (res.statusCode != 200) {
      _log('backend geocode HTTP ${res.statusCode} ${res.body}');
      return null;
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final name = map['display_name'] as String?;
    if (name == null || name.trim().isEmpty) {
      _log('FAIL: empty display_name');
      return null;
    }
    _log('OK (web): $name');
    return name.trim();
  } catch (e, st) {
    _log('FAIL: exception: $e');
    _log('stack: $st');
    return null;
  }
}

/// Converts coordinates to a single-line address (no lat/lng shown to users).
Future<String?> reverseGeocode(double latitude, double longitude) async {
  final key = _cacheKey(latitude, longitude);
  final now = DateTime.now();
  final cached = _reverseCache[key];
  if (cached != null && cached.expiresAt.isAfter(now)) {
    return cached.value;
  }

  final existing = _inflight[key];
  if (existing != null) {
    return existing;
  }

  _log('reverseGeocode(lat=$latitude, lng=$longitude)');
  // Use backend reverse-geocode on all platforms to avoid plugin/runtime variance.
  final fut = _reverseGeocodeWeb(latitude, longitude);
  _inflight[key] = fut;
  try {
    final v = await fut;
    // Cache failures longer to avoid hammering Nominatim after 429 / 502 bursts.
    _reverseCache[key] = _CacheEntry(
      v,
      now.add(Duration(minutes: v == null ? 5 : 30)),
    );
    return v;
  } finally {
    _inflight.remove(key);
  }
}
