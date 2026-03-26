import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/sport_event.dart';

/// Loads and caches nearby [SportEvent] rows from FastAPI.
class EventProvider extends ChangeNotifier {
  EventProvider();

  final List<SportEvent> _events = [];
  final List<SportEvent> _myEvents = [];
  String? errorMessage;
  String? myEventsError;
  bool isLoading = false;
  bool myEventsLoading = false;

  List<SportEvent> get events => List.unmodifiable(_events);

  /// Events created by the signed-in organizer (`GET /events/me`).
  List<SportEvent> get myEvents => List.unmodifiable(_myEvents);

  /// Calls `GET /events/nearby` and replaces [events].
  Future<void> fetchNearbyEvents(double lat, double long,
      {double radiusKm = 50}) async {
    isLoading = true;
    errorMessage = null;
    _events.clear();
    notifyListeners();

    final uri = Uri.parse('${ApiConfig.baseUrl}/events/nearby').replace(
      queryParameters: {
        'lat': lat.toString(),
        'long': long.toString(),
        'radius': radiusKm.toString(),
      },
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        errorMessage = 'HTTP ${res.statusCode}: ${res.body}';
        _events.clear();
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      _events
        ..clear()
        ..addAll(
          list.map((e) => SportEvent.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      errorMessage = e.toString();
      _events.clear();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Requires [Authorization] header (see [AuthProvider.authHeaders]).
  Future<void> fetchMyEvents(Map<String, String> authHeaders) async {
    if (authHeaders.isEmpty) {
      myEventsError = 'Sign in to see your events.';
      _myEvents.clear();
      notifyListeners();
      return;
    }

    myEventsLoading = true;
    myEventsError = null;
    notifyListeners();

    final uri = Uri.parse('${ApiConfig.baseUrl}/events/me');
    try {
      final res = await http.get(uri, headers: authHeaders);
      if (res.statusCode != 200) {
        myEventsError = 'Could not load events (HTTP ${res.statusCode}).';
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      _myEvents
        ..clear()
        ..addAll(
          list.map((e) => SportEvent.fromJson(e as Map<String, dynamic>)),
        );
      myEventsError = null;
    } catch (e) {
      myEventsError = e.toString();
    } finally {
      myEventsLoading = false;
      notifyListeners();
    }
  }
}
