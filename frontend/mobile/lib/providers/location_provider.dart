import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/reverse_geocode.dart';
import 'auth_provider.dart';

const _kLatKey = 'user_last_lat';
const _kLngKey = 'user_last_lng';
const _kAddressKey = 'user_last_address';

/// Loads/saves the device position in [SharedPreferences] and syncs to the API when logged in.
class LocationProvider extends ChangeNotifier {
  LocationProvider(this._auth) {
    _auth.addListener(_onAuthChanged);
  }

  /// Shared with [FirstLaunchGate] — do not rename without a migration.
  static const String permissionsOnboardingPrefsKey =
      'permissions_onboarding_v1_done';

  final AuthProvider _auth;

  double? _lat;
  double? _lng;
  String? _errorMessage;
  bool _loading = false;
  String? _address;
  bool _addressLoading = false;
  bool _geocodeEnabled = false;
  /// Set by the last [syncToServer] attempt (when logged in).
  bool _lastServerSyncOk = false;

  double? get lat => _lat;
  double? get lng => _lng;
  String? get errorMessage => _errorMessage;
  bool get loading => _loading;

  /// Human-readable address for [effectiveLat] / [effectiveLng] (never raw coordinates).
  String get addressDisplay {
    final cached = _address?.trim();
    if (_addressLoading && (cached == null || cached.isEmpty)) {
      return 'Loading address…';
    }
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (_addressLoading) {
      return 'Updating address…';
    }
    return 'Address unavailable';
  }

  bool get addressLoading => _addressLoading;

  /// Whether the last [syncToServer] call returned HTTP 200 (profile updated on backend).
  bool get lastServerSyncSucceeded => _lastServerSyncOk;

  static const double _fallbackLat = 37.7749;
  static const double _fallbackLng = -122.4194;

  double get effectiveLat => _lat ?? _fallbackLat;
  double get effectiveLng => _lng ?? _fallbackLng;

  /// Loads last saved coordinates from disk. Does not request permission — call
  /// [refreshFromDevice] after the first frame (see [LocationPermissionBootstrap]).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lat = prefs.getDouble(_kLatKey);
    _lng = prefs.getDouble(_kLngKey);
    _address = prefs.getString(_kAddressKey);
    final onboardingDone =
        prefs.getBool(permissionsOnboardingPrefsKey) == true;
    final legacyHasCoords = _lat != null && _lng != null;
    _geocodeEnabled = onboardingDone || legacyHasCoords;
    notifyListeners();
    if (_geocodeEnabled) {
      unawaited(refreshAddress());
    }
  }

  /// After first-run welcome: save flag, request GPS fix when possible, then geocode.
  Future<void> completePermissionsOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionsOnboardingPrefsKey, true);
    _geocodeEnabled = true;
    notifyListeners();
    await refreshFromDevice();
    if (_address == null || _address!.trim().isEmpty) {
      await refreshAddress();
    }
  }

  /// Resolves a postal-style address from current [effectiveLat] / [effectiveLng].
  Future<void> refreshAddress() async {
    if (!_geocodeEnabled) {
      return;
    }
    _addressLoading = true;
    notifyListeners();
    try {
      final addr = await reverseGeocode(effectiveLat, effectiveLng);
      _address = (addr != null && addr.isNotEmpty) ? addr : null;
      final prefs = await SharedPreferences.getInstance();
      if (_address != null) {
        await prefs.setString(_kAddressKey, _address!);
      } else {
        await prefs.remove(_kAddressKey);
      }
    } finally {
      _addressLoading = false;
      notifyListeners();
    }
  }

  void _onAuthChanged() {
    if (_auth.isLoggedIn && _lat != null && _lng != null) {
      unawaited(syncToServer());
    }
  }

  /// Requests permission, reads GPS, persists locally, and syncs to the API when signed in.
  /// Returns `true` if a position was obtained (even if server sync failed).
  Future<bool> refreshFromDevice() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Location services are disabled.';
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Location permission denied.';
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        _errorMessage =
            'Location permission is blocked. Enable it in Settings for nearby games.';
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
      await _persistLocal();
      notifyListeners();
      if (_auth.isLoggedIn) {
        await syncToServer();
      }
      await refreshAddress();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lat != null && _lng != null) {
      await prefs.setDouble(_kLatKey, _lat!);
      await prefs.setDouble(_kLngKey, _lng!);
    }
  }

  /// Opens system app settings so the user can turn location on for this app.
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Sends [last known coordinates] to `PATCH /auth/me/location` and merges the profile on success.
  Future<bool> syncToServer() async {
    final t = _auth.token;
    if (t == null || _lat == null || _lng == null) {
      _lastServerSyncOk = false;
      return false;
    }
    _lastServerSyncOk = false;
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/me/location');
    try {
      final res = await http.patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $t',
        },
        body: jsonEncode({'lat': _lat, 'long': _lng}),
      );
      if (res.statusCode == 200) {
        try {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          _auth.applyUserFromJson(map);
        } catch (_) {}
        _lastServerSyncOk = true;
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Offline or server down — local prefs still hold the last fix.
    }
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
