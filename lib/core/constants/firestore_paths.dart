/// Centralized Firestore collection path helpers.
/// All repository classes use these to avoid hardcoded strings.
class FirestorePaths {
  FirestorePaths._();

  // Top-level collections
  static String users() => 'users';
  static String user(String userId) => 'users/$userId';
  static String inviteCodes() => 'inviteCodes';

  // Association-scoped collections
  static String associations() => 'associations';
  static String association(String assocId) => 'associations/$assocId';

  static String seasons(String assocId) =>
      'associations/$assocId/seasons';
  static String season(String assocId, String seasonId) =>
      'associations/$assocId/seasons/$seasonId';

  static String divisions(String assocId) =>
      'associations/$assocId/divisions';
  static String division(String assocId, String divisionId) =>
      'associations/$assocId/divisions/$divisionId';

  static String teams(String assocId) =>
      'associations/$assocId/teams';
  static String team(String assocId, String teamId) =>
      'associations/$assocId/teams/$teamId';

  static String posts(String assocId) =>
      'associations/$assocId/posts';
  static String post(String assocId, String postId) =>
      'associations/$assocId/posts/$postId';

  static String events(String assocId) =>
      'associations/$assocId/events';
  static String event(String assocId, String eventId) =>
      'associations/$assocId/events/$eventId';

  static String gameStats(String assocId) =>
      'associations/$assocId/gameStats';
  static String gameStat(String assocId, String eventId) =>
      'associations/$assocId/gameStats/$eventId';

  static String playerSeasonStats(String assocId) =>
      'associations/$assocId/playerSeasonStats';
  static String playerSeasonStat(String assocId, String compositeId) =>
      'associations/$assocId/playerSeasonStats/$compositeId';

  static String leaderboards(String assocId) =>
      'associations/$assocId/leaderboard';
  static String leaderboard(String assocId, String compositeId) =>
      'associations/$assocId/leaderboard/$compositeId';

  static String teamSeasonStats(String assocId) =>
      'associations/$assocId/teamSeasonStats';
  static String teamSeasonStat(String assocId, String compositeId) =>
      'associations/$assocId/teamSeasonStats/$compositeId';

  static String standings(String assocId) =>
      'associations/$assocId/standings';
  static String standing(String assocId, String id) =>
      'associations/$assocId/standings/$id';
}
