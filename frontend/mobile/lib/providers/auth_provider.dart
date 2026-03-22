import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/app_user.dart';

const _kTokenKey = 'auth_token';

/// Persists JWT and user profile; drives login / register / logout.
class AuthProvider extends ChangeNotifier {
  AuthProvider();

  bool loading = true;
  String? token;
  AppUser? user;
  String? lastError;

  bool get isLoggedIn => token != null && user != null;

  Future<void> init() async {
    loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kTokenKey);
      if (saved == null || saved.isEmpty) {
        token = null;
        user = null;
        return;
      }
      token = saved;
      await _fetchMe();
    } catch (e) {
      token = null;
      user = null;
      lastError = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchMe() async {
    final t = token;
    if (t == null) {
      return;
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/me');
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $t'},
    );
    if (res.statusCode != 200) {
      token = null;
      user = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokenKey);
      return;
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    user = AppUser.fromJson(map);
  }

  Future<void> _persistToken(String? t) async {
    final prefs = await SharedPreferences.getInstance();
    if (t == null || t.isEmpty) {
      await prefs.remove(_kTokenKey);
    } else {
      await prefs.setString(_kTokenKey, t);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    lastError = null;
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/login');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim(), 'password': password}),
      );
      if (res.statusCode != 200) {
        lastError = _parseError(res.body) ?? 'Login failed (${res.statusCode})';
        notifyListeners();
        return false;
      }
      await _applyAuthResponse(res.body);
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    lastError = null;
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/register');
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
          'role': role,
        }),
      );
      if (res.statusCode != 200) {
        lastError = _parseError(res.body) ?? 'Registration failed (${res.statusCode})';
        notifyListeners();
        return false;
      }
      await _applyAuthResponse(res.body);
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> _applyAuthResponse(String body) async {
    final map = jsonDecode(body) as Map<String, dynamic>;
    token = map['access_token'] as String?;
    await _persistToken(token);
    user = AppUser.fromJson(map['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  String? _parseError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final detail = m['detail'];
      if (detail is String) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'] as String;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> logout() async {
    token = null;
    user = null;
    await _persistToken(null);
    notifyListeners();
  }

  /// Bearer token for authenticated API calls (optional).
  Map<String, String> authHeaders() {
    final t = token;
    if (t == null) {
      return {};
    }
    return {'Authorization': 'Bearer $t'};
  }
}
