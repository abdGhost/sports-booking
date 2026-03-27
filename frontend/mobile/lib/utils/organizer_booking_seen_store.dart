import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which [booking_id]s the organizer has already viewed (per event).
///
/// Used to show a "new registration" badge on My events until they open the
/// roster on [OrganizerDashboard] for that event.
class OrganizerBookingSeenStore {
  OrganizerBookingSeenStore._();
  static final OrganizerBookingSeenStore instance = OrganizerBookingSeenStore._();

  static const _keyPrefix = 'org_seen_booking_ids_v1_';

  Future<Set<int>> loadAcknowledged(int eventId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_keyPrefix$eventId');
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => e is int ? e : (e as num).toInt())
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Marks [bookingIds] as seen. Merges with anything previously acknowledged.
  Future<void> acknowledgeBookings(int eventId, Set<int> bookingIds) async {
    if (bookingIds.isEmpty) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    final prev = await loadAcknowledged(eventId);
    prev.addAll(bookingIds);
    final sorted = prev.toList()..sort();
    await p.setString('$_keyPrefix$eventId', jsonEncode(sorted));
  }
}
