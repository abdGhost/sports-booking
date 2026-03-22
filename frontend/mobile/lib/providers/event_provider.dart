import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/sport_event.dart';

/// Loads and caches nearby [SportEvent] rows from FastAPI.
class EventProvider extends ChangeNotifier {
  EventProvider();

  final List<SportEvent> _events = [];
  String? errorMessage;
  bool isLoading = false;

  List<SportEvent> get events => List.unmodifiable(_events);

  /// Calls `GET /events/nearby` and replaces [events].
  Future<void> fetchNearbyEvents(double lat, double long,
      {double radiusKm = 50}) async {
    isLoading = true;
    errorMessage = null;
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
}
