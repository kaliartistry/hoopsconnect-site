import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/public_stat_export_service.dart';

const _snapshotHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _retractedHash =
    'cccccccccccccccccccccccccccccccc'
    'cccccccccccccccccccccccccccccccc';

void main() {
  group('spreadsheet formula escaping', () {
    test('prefixes formula-capable text after leading whitespace', () {
      expect(PublicStatExportService.escapeSpreadsheetText('=1+1'), "'=1+1");
      expect(PublicStatExportService.escapeSpreadsheetText(' +cmd'), "' +cmd");
      expect(PublicStatExportService.escapeSpreadsheetText('-2+3'), "'-2+3");
      expect(
        PublicStatExportService.escapeSpreadsheetText('@SUM(A1)'),
        "'@SUM(A1)",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\t=1+1'),
        "'\t=1+1",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\r=1+1'),
        "'\r=1+1",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\n=1+1'),
        "'\n=1+1",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\u0000=1+1'),
        "'\u0000=1+1",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\ufeff=1+1'),
        "'\ufeff=1+1",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('\u200b@SUM(A1)'),
        "'\u200b@SUM(A1)",
      );
      expect(
        PublicStatExportService.escapeSpreadsheetText('Kingston'),
        'Kingston',
      );
      expect(PublicStatExportService.escapeSpreadsheetText("'=1+1"), "'=1+1");
    });
  });

  test('game CSV binds every row to one snapshot and result version', () {
    final snapshot = _snapshot();
    final resultVersion = snapshot.schedule.single.resultVersion!;

    final csv = PublicStatExportService.gameCsv(
      snapshot: snapshot,
      gameId: 'game-1',
      grant: PublicExportGrant.media,
    );

    expect(csv, contains('"game_result"'));
    expect(csv, contains('"player_line"'));
    expect(csv, contains("\"'=HYPERLINK(\"\"bad\"\")\""));
    expect(csv, contains("\"' +Away\""));
    expect(csv, contains("\"'@Player\""));
    expect(RegExp('a{64}').allMatches(csv).length, 4);
    expect(resultVersion.length, 64);
    expect(csv, contains('Unknown'));
    expect(csv, isNot(contains('private@example.com')));
    expect(csv, isNot(contains('guardian')));
    for (final row in csv.trim().split('\r\n').skip(1)) {
      expect(row, contains(_snapshotHash));
      expect(row, contains(resultVersion));
    }
  });

  test('player identity rows are excluded without the field-level grant', () {
    final csv = PublicStatExportService.gameCsv(
      snapshot: _snapshot(),
      gameId: 'game-1',
      grant: const PublicExportGrant(
        canExportGame: true,
        canExportSeason: false,
        canExportPlayerIdentity: false,
      ),
    );

    expect(csv, isNot(contains('"player_line"')));
    expect(csv, isNot(contains("'@Player")));
    expect(csv, isNot(contains('player-1')));
  });

  test('player identity rows are excluded without a privacy epoch', () {
    final snapshot = _snapshot(
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1.1',
        snapshotVersion: _snapshotHash,
        verificationStatus: 'legacyApproved',
        state: PublicReleaseState.published,
        privacyEpoch: null,
        generatedAt: DateTime.utc(2026, 9, 10, 21),
      ),
    );

    final csv = PublicStatExportService.gameCsv(
      snapshot: snapshot,
      gameId: 'game-1',
      grant: PublicExportGrant.media,
    );

    expect(csv, isNot(contains('"player_line"')));
    expect(csv, isNot(contains("'@Player")));
    expect(csv, isNot(contains('player-1')));
  });

  test('export capabilities fail closed', () {
    expect(
      () => PublicStatExportService.gameCsv(
        snapshot: _snapshot(),
        gameId: 'game-1',
        grant: PublicExportGrant.none,
      ),
      throwsA(isA<PublicExportDenied>()),
    );
    expect(
      () => PublicStatExportService.seasonCsv(
        snapshot: _snapshot(),
        grant: const PublicExportGrant(
          canExportGame: true,
          canExportSeason: false,
          canExportPlayerIdentity: true,
        ),
      ),
      throwsA(isA<PublicExportDenied>()),
    );
  });

  test('unversioned and withdrawn snapshots cannot create artifacts', () {
    final published = _snapshot();
    final unversioned = _snapshot(
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1',
        snapshotVersion: null,
        verificationStatus: 'legacyApproved',
        state: PublicReleaseState.published,
        privacyEpoch: null,
        generatedAt: DateTime.utc(2026, 9, 10, 21),
      ),
    );
    final retracted = _snapshot(
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1.1',
        snapshotVersion: _retractedHash,
        verificationStatus: 'legacyApproved',
        state: PublicReleaseState.retracted,
        privacyEpoch: 8,
        generatedAt: DateTime.utc(2026, 9, 10, 21),
      ),
    );
    final unverified = _snapshot(
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1.1',
        snapshotVersion: _snapshotHash,
        verificationStatus: 'unknown',
        state: PublicReleaseState.published,
        privacyEpoch: 8,
        generatedAt: DateTime.utc(2026, 9, 10, 21),
      ),
    );

    expect(published.canCreatePublishedArtifacts, isTrue);
    for (final snapshot in [unversioned, retracted, unverified]) {
      expect(
        () => PublicStatExportService.gameCsv(
          snapshot: snapshot,
          gameId: 'game-1',
          grant: PublicExportGrant.media,
        ),
        throwsA(isA<PublicExportUnavailable>()),
      );
    }
  });

  test('season CSV includes games, standings, and cleared leaders', () {
    final csv = PublicStatExportService.seasonCsv(
      snapshot: _snapshot(),
      grant: PublicExportGrant.media,
    );

    expect(csv, contains('"game_result"'));
    expect(csv, contains('"standing"'));
    expect(csv, contains('"leader"'));
    expect(csv, contains('"ppg"'));
    expect(csv, contains('"Ranked Player"'));
    expect(csv, contains('"game_status"'));
    expect(csv, contains('"winning_percentage"'));
    expect(csv, contains('"ranking_policy"'));
    expect(csv, contains('"qualification_label"'));
    expect(csv, contains('"Winning percentage"'));
    expect(csv, contains('"Minimum 1 game"'));
  });
}

PublicLeagueSnapshot _snapshot({PublicSnapshotVersion? version}) {
  final resolvedVersion =
      version ??
      PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1.1',
        snapshotVersion: _snapshotHash,
        verificationStatus: 'legacyApproved',
        state: PublicReleaseState.published,
        privacyEpoch: 8,
        generatedAt: DateTime.utc(2026, 9, 10, 21),
      );
  return PublicLeagueSnapshot(
    leagueName: 'Jamaica Basketball Association',
    leagueShortName: 'JBA',
    seasonId: 'season-1',
    seasonName: '2026 NBL',
    standingsPolicyLabel: 'Winning percentage',
    version: resolvedVersion,
    divisions: const [PublicDivision(divisionId: 'premier', name: 'Premier')],
    teams: const [
      PublicTeam(
        teamId: 'home',
        name: '=HYPERLINK("bad")',
        divisionId: 'premier',
      ),
      PublicTeam(teamId: 'away', name: ' +Away', divisionId: 'premier'),
    ],
    schedule: [
      PublicGame(
        gameId: 'game-1',
        title: 'Final',
        startTime: DateTime.utc(2026, 9, 10, 20),
        venue: '-Venue formula',
        divisionId: 'premier',
        homeTeamId: 'home',
        homeTeamName: '=HYPERLINK("bad")',
        awayTeamId: 'away',
        awayTeamName: ' +Away',
        homeScore: 82,
        awayScore: 79,
        status: PublicGameStatus.finalResult,
        periodScores: const [
          PublicPeriodScore(period: 1, homeScore: 20, awayScore: 18),
          PublicPeriodScore(period: 2, homeScore: 22, awayScore: 21),
        ],
        playerLines: const [
          PublicPlayerGameLine(
            playerId: 'player-1',
            displayName: '@Player',
            teamId: 'home',
            points: 20,
            twoPointMade: 6,
            twoPointAttempted: 10,
            turnovers: 2,
          ),
        ],
      ).withComputedResultVersion(),
    ],
    standings: const [
      PublicStanding(
        teamId: 'home',
        teamName: '=HYPERLINK("bad")',
        divisionId: 'premier',
        rank: 1,
        rankStatus: PublicRankStatus.ranked,
        wins: 1,
        losses: 0,
        pct: 1,
        pointsFor: 82,
        pointsAgainst: 79,
      ),
    ],
    leaderboards: const [
      PublicLeaderboard(
        category: 'ppg',
        divisionId: 'premier',
        qualificationLabel: 'Minimum 1 game',
        rankings: [
          PublicLeader(
            playerId: 'ranked-player',
            displayName: 'Ranked Player',
            teamId: 'home',
            teamName: '=HYPERLINK("bad")',
            value: 20,
            gamesPlayed: 1,
          ),
        ],
      ),
    ],
  );
}
