import 'dart:math' as math;

/// Earth mean radius in kilometers (WGS84 approximation).
const double earthRadiusKm = 6371.0;

/// Haversine great-circle distance between two WGS84 coordinates (degrees).
double haversineDistanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final p1 = lat1 * math.pi / 180.0;
  final p2 = lat2 * math.pi / 180.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) *
          math.cos(p2) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.asin(math.min(1.0, math.sqrt(a)));
  return earthRadiusKm * c;
}

/// Player with a measurable skill used for balancing.
class RatedPlayer {
  RatedPlayer({required this.id, required this.skillRating});

  final String id;
  final double skillRating;
}

/// Splits [players] into two teams with sizes differing by at most one, such that
/// the absolute difference between **average** [skillRating] on each team is small.
///
/// Uses greedy "snake" assignment on players sorted by descending skill: each pick
/// goes to the team with the lower current **total** rating, which tends to balance
/// both sums and averages for fixed team sizes.
List<List<RatedPlayer>> balancedTeamsBySkill(List<RatedPlayer> players) {
  if (players.isEmpty) {
    return [[], []];
  }
  if (players.length == 1) {
    return [[players.first], []];
  }

  final sorted = [...players]..sort((a, b) => b.skillRating.compareTo(a.skillRating));

  final teamA = <RatedPlayer>[];
  final teamB = <RatedPlayer>[];
  double sumA = 0;
  double sumB = 0;

  for (final p in sorted) {
    if (sumA <= sumB) {
      teamA.add(p);
      sumA += p.skillRating;
    } else {
      teamB.add(p);
      sumB += p.skillRating;
    }
  }
  return [teamA, teamB];
}
