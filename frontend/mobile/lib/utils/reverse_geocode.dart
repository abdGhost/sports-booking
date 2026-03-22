import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

void _log(String message) {
  debugPrint('[Geocode] $message');
}

Future<String?> _reverseGeocodeWeb(double lat, double lng) async {
  try {
    final uri = Uri.parse('${ApiConfig.baseUrl}/geocode/reverse').replace(
      queryParameters: {'lat': lat.toString(), 'lon': lng.toString()},
    );
    final res = await http.get(uri);
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
  _log('reverseGeocode(lat=$latitude, lng=$longitude)');
  // Use backend reverse-geocode on all platforms to avoid plugin/runtime variance.
  return _reverseGeocodeWeb(latitude, longitude);
}
